# = AttachmentOptions
#
# Encapsulates options for the +has_attached_file+ declaration in the Asset module
#
module AttachmentOptions

  ##
  # Options for +has_attached_file+'.  Uses Radiant::Config['assets.storage'] to determine
  # the appropriate set of options: +filesystem+ (default), +cloud_files+ or 'cloud_file', and 's3'
  # 
  # options: overrides for +has_attached_file+
  #
  def attachment_options( options = {} )
    case _c('assets.storage')
    when 's3'
      s3_attachment_options
    when 'cloud_files', 'cloud_file'
      cloud_file_attachment_options
    when nil, '', 'filesystem'
      filesystem_attachment_options
    else
      raise 'Unkown assets storage engine: '+_c('assets.storage').to_s
    end.merge(options)
  end

  ##
  # Builder for filesystem storage
  #
  def filesystem_attachment_options
    build_attachment_options({
      :storage => :filesystem,
      :url => _c('assets.url') ? _c('assets.url') : "/:class/:id/:basename:no_original_style.:extension", 
      :path => _c('assets.path') ? _c('assets.path') : ":rails_root/public/:class/:id/:basename:no_original_style.:extension"
    })
  end

  ##
  # Builder for AWS S3 storage
  #
  def s3_attachment_options
    build_attachment_options({
      :storage => :s3,
      :bucket => _c('assets.s3.bucket'),
      :path => _c('assets.path') ? _c('assets.path') : ':class/:id/:basename:no_original_style.:extension',
      # :s3_host_alias => _c('assets.s3.host_alias'), # TODO add cloud front support
      :s3_credentials => {
        :access_key_id => _c('assets.s3.key'),
        :secret_access_key => _c('assets.s3.secret'),
      }
    })
  end

  ##
  # Builder for Rackspace CloudFiles storage
  #
  def cloud_file_attachment_options
    build_attachment_options({
      :storage => :cloud_file,
      :container => _c('assets.cloud_files.container'),
      :path => _c('assets.path') ? _c('assets.path') : ':class/:id/:basename:no_original_style.:extension',
      :cloudfiles_credentials => {
        :username => _c('assets.cloud_files.username'),
        :api_key => _c('assets.cloud_files.api_key'),
        :servicenet => %w(true 1 yes).include?((_c('assets.cloud_files.servicenet') || '').downcase)
      }
    })
  end

protected

  ##
  # The base for the builders.
  #
  # options: overrides for +has_attached_file+
  #
  def build_attachment_options(options = {})
    {
      # this allows us to set processors per file type, and to add more in other extensions
      :processors => lambda {|instance| instance.choose_processors },
      # and this lets extensions add thumbnailers (and also usefully defers the call)
      :styles => lambda { thumbnail_definitions },
      :whiny_thumbnails => %w(true 1 yes).include?((_c('assets.whiny_thumbnails') || '').downcase),
      :whiny => %w(true 1 yes).include?((_c('assets.whiny_thumbnails') || '').downcase)
    }.merge(options)
  end

  def radiant_config( key )
    v = Radiant::Config[key] 
    v = v.strip unless v.blank? or v.strip.blank?
    return v
  end
  alias_method :_c, :radiant_config
end
