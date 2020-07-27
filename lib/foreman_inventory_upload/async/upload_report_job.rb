require 'tempfile'

module ForemanInventoryUpload
  module Async
    class UploadReportJob < ShellProcess
      def self.output_label(label)
        "upload_for_#{label}"
      end

      def perform(filename, organization_id)
        @filename = filename
        @organization = Organization.find(organization_id)

        Tempfile.create([@organization.name, '.pem']) do |cer_file|
          cer_file.write(rh_credentials[:cert])
          cer_file.write(rh_credentials[:key])
          cer_file.flush
          @cer_path = cer_file.path
          super(UploadReportJob.output_label(organization_id))
        end
      end

      def command
        ['/bin/bash', File.join(File.dirname(@filename), ForemanInventoryUpload.upload_script_file)]
      end

      def env
        env_vars = super.merge(
          'FILES' => @filename,
          'CER_PATH' => @cer_path
        )
        if http_proxy_string
          env_vars['http_proxy'] = http_proxy_string
          env_vars['https_proxy'] = http_proxy_string
        end
        env_vars
      end

      def http_proxy_string
        @http_proxy_string ||=
          HttpProxy.default_global_content_proxy&.full_url ||
          cdn_proxy ||
          global_foreman_proxy
      end

      def rh_credentials
        @rh_credentials ||= begin
          candlepin_id_certificate = @organization.owner_details['upstreamConsumer']['idCert']
          {
            cert: candlepin_id_certificate['cert'],
            key: candlepin_id_certificate['key'],
          }
        end
      end

      def cdn_proxy
        cdn_settings = SETTINGS[:katello][:cdn_proxy] || {}

        return nil unless cdn_settings[:host]

        proxy_uri = URI('')

        original_uri = URI.parse(cdn_settings[:host])

        proxy_uri.scheme = original_uri.scheme || 'http'
        proxy_uri.host = original_uri.host || original_uri.path
        proxy_uri.port = cdn_settings[:port]
        proxy_uri.user = cdn_settings[:user]
        proxy_uri.password = cdn_settings[:password]

        proxy_uri.to_s
      rescue URI::Error => e
        logger.warn("cdn_proxy parsing failed: #{e}")
        nil
      end

      def global_foreman_proxy
        Setting[:http_proxy]
      end
    end
  end
end
