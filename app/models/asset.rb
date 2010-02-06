require 'mime_type_ext'
 
class Asset < ActiveRecord::Base
  extend AttachmentOptions
  
  @@known_types = []
  cattr_accessor :known_types
 
  # type declaration machinery is consolidated here so that other extensions can add more types
  # for example: Asset.register_type(:gps, %w{application/gpx+xml application/tcx+xml})
  # the main Asset register_type() calls are in the class definition below after validation
  
  def self.register_type(type, mimes)
    constname = type.to_s.upcase.to_sym
    Mime.send(:remove_const, constname) if Mime.const_defined?(constname)
    Mime::Type.register mimes.shift, type, mimes       # Mime::Type.register 'image/png', :image, %w[image/x-png image/jpeg image/pjpeg image/jpg image/gif]
 
    self.class.send :define_method, "#{type}?".intern do |content_type|
      Mime::Type.lookup_by_extension(type.to_s) == content_type.to_s
    end
  
    define_method "#{type}?".intern do
      self.class.send "#{type}?".intern, asset_content_type
    end
 
    self.class.send :define_method, "#{type}_condition".intern do
      types = Mime::Type.lookup_by_extension(type.to_s).all_types
      send(:sanitize_sql, ['asset_content_type IN (?)', types])
    end
 
    self.class.send :define_method, "not_#{type}_condition".intern do
      types = Mime::Type.lookup_by_extension(type.to_s).all_types
      send(:sanitize_sql, ['NOT asset_content_type IN (?)', types])
    end
  
    named_scope type.to_s.pluralize.intern, :conditions => self.send("#{type}_condition".intern) do
      def paged (options={})
        paginate({:per_page => 20, :page => 1}.merge(options))
      end
    end
 
    named_scope "not_#{type.to_s.pluralize}".intern, :conditions => self.send("not_#{type}_condition".intern) do
      def paged (options={})
        paginate({:per_page => 20, :page => 1}.merge(options))
      end
    end
    
    known_types.push(type)
  end
  
  def self.known_type?(type)
    known_types.include?(type)
  end
 
  # 'other' here means 'document', really: anything that is not image, audio or video.
  
  def other?
    self.class.other?(asset_content_type)
  end
 
  def self.other?(content_type)
    !self.mime_types_not_considered_other.include? content_type.to_s
  end
  
  # the lambda delays interpolation, allowing extensions to affect the other_condition
  named_scope :others, lambda {{:conditions => self.other_condition}}
  known_types.push(:other)
  
  # this is just a convenience to omit site-layout images from galleries
  named_scope :furniture, {:conditions => 'assets.furniture = 1'}
  named_scope :not_furniture, {:conditions => 'assets.furniture = 0 or assets.furniture is null'}
  named_scope :newest_first, { :order => 'created_at DESC'}
  
  def self.other_condition
    send(:sanitize_sql, ['asset_content_type NOT IN (?)', self.mime_types_not_considered_other])
  end
 
  def self.mime_types_not_considered_other
    Mime::IMAGE.all_types + Mime::AUDIO.all_types + Mime::MOVIE.all_types  
  end
    
  class << self
    def search(search, filter, page)
      unless search.blank?
 
        search_cond_sql = []
        search_cond_sql << 'LOWER(asset_file_name) LIKE (:term)'
        search_cond_sql << 'LOWER(title) LIKE (:term)'
        search_cond_sql << 'LOWER(caption) LIKE (:term)'
 
        cond_sql = search_cond_sql.join(" or ")
 
        @conditions = [cond_sql, {:term => "%#{search.downcase}%" }]
      else
        @conditions = []
      end
 
      options = { :conditions => @conditions,
                  :order => 'created_at DESC',
                  :page => page,
                  :per_page => 10 }
 
      @file_types = filter.blank? ? [] : filter.keys
      if not @file_types.empty?
        options[:total_entries] = count_by_conditions
        Asset.paginate_by_content_types(@file_types, :all, options )
      else
        Asset.paginate(:all, options)
      end
    end
 
    def find_all_by_content_types(types, *args)
      with_content_types(types) { find *args }
    end
 
    def with_content_types(types, &block)
      with_scope(:find => { :conditions => types_to_conditions(types).join(' OR ') }, &block)
    end
    
    def count_by_conditions
      type_conditions = @file_types.blank? ? nil : Asset.types_to_conditions(@file_types.dup).join(" OR ")
      @count_by_conditions ||= @conditions.empty? ? Asset.count(:all, :conditions => type_conditions) : Asset.count(:all, :conditions => @conditions)
    end
    
    def types_to_conditions(types)
      types.collect! { |t| '(' + send("#{t}_condition") + ')' }
    end
    
    def thumbnail_sizes
      if Radiant::Config.table_exists? && Radiant::Config["assets.additional_thumbnails"]
        thumbnails = additional_thumbnails
      else
        thumbnails = {}
      end
      thumbnails[:icon] = ['42x42#', :png]
      thumbnails[:thumbnail] = ['100x100>', :png]
      thumbnails
    end
 
    def thumbnail_names
      thumbnail_sizes.keys
    end
    
    # returns a descriptive list suitable for use as options in a select box
    
    def thumbnail_options
      asset_sizes = thumbnail_sizes.collect{|k,v| 
        size_id = k
        size_description = "#{k}: "
        size_description << (v.is_a?(Array) ? v.join(' as ') : v)
        [size_description, size_id] 
      }.sort_by{|pair| pair.last.to_s}
      asset_sizes.unshift ['Original (as uploaded)', 'original']
      asset_sizes
    end
    
    # this is just a pointer that can be alias-chained in other extensions to add to or replace the list of thumbnail mechanisms
    # its invocation is delayed with a lambda in has_attached_file so that it isn't called when the extension loads, but when an attachment initializes:
    # that way we can be sure that all the related extensions have loaded and all the alias_chains are in place.
    
    def thumbnail_definitions
      thumbnail_sizes
    end
 
  private
    def additional_thumbnails
      Radiant::Config["assets.additional_thumbnails"].gsub(' ','').split(',').collect{|s| s.split('=')}.inject({}) {|ha, (k, v)| ha[k.to_sym] = v; ha}
    end
  end
  
  # order_by 'title'
 
  has_attached_file :asset, attachment_options
                                 
  has_many :page_attachments, :dependent => :destroy
  has_many :pages, :through => :page_attachments
 
  belongs_to :created_by, :class_name => 'User'
  belongs_to :updated_by, :class_name => 'User'
  
  validates_attachment_presence :asset, :message => "You must choose a file to upload!"
  validates_attachment_content_type :asset, 
    :content_type => Radiant::Config["assets.content_types"].gsub(' ','').split(',') if Radiant::Config.table_exists? && Radiant::Config["assets.content_types"] && Radiant::Config["assets.skip_filetype_validation"] == nil
  validates_attachment_size :asset, 
    :less_than => Radiant::Config["assets.max_asset_size"].to_i.megabytes if Radiant::Config.table_exists? && Radiant::Config["assets.max_asset_size"]
    
  before_save :assign_title
  
  register_type :image, %w[image/png image/x-png image/jpeg image/pjpeg image/jpg image/gif]
  register_type :video, %w[video/mpeg video/mp4 video/ogg video/quicktime video/x-ms-wmv video/x-flv]
  register_type :audio, %w[audio/mpeg audio/mpg audio/ogg application/ogg audio/x-ms-wma audio/vnd.rn-realaudio audio/x-wav]
  register_type :swf, %w[application/x-shockwave-flash]
  register_type :pdf, %w[application/pdf]
 
  # alias for backwards-compatibility: movie can be video or swf
  register_type :movie, Mime::SWF.all_types + Mime::VIDEO.all_types
 
  def thumbnail(size='original')
    return asset.url if size == 'original'
    case 
      when self.pdf?   : "/images/assets/pdf_#{size.to_s}.png"
      when self.movie? : "/images/assets/movie_#{size.to_s}.png"
      when self.video? : "/images/assets/movie_#{size.to_s}.png"
      when self.swf? : "/images/assets/movie_#{size.to_s}.png" #TODO: special icon for swf-files
      when self.audio? : "/images/assets/audio_#{size.to_s}.png"
      when self.other? : "/images/assets/doc_#{size.to_s}.png"
    else
      self.asset.url(size.to_sym)
    end
  end
  
  def generate_style(name, args={}) 
    size = args[:size] 
    format = args[:format] || :jpg
    asset = self.asset
    unless asset.exists?(name.to_sym)
      self.asset.styles[name.to_sym] = { :geometry => size, :format => format, :whiny => true, :convert_options => "", :processors => [:thumbnail] } 
      self.asset.reprocess!
    end
  end
  
  # this has been added to support other extensions that want to add processors 
  # eg paperclipped_gps uses gpsbabel in the same way as paperclipped uses imagemagick
  # I also mean to add a video thumbnailer using ffmpeg 
  
  def choose_processors
    [:thumbnail]
  end
 
  def basename
    File.basename(asset_file_name, ".*") if asset_file_name
  end
  
  def extension
    asset_file_name.split('.').last.downcase if asset_file_name
  end
  
  def dimensions(size='original')
    @dimensions ||= {}
    @dimensions[size] ||= image? && begin
      image_file = "#{RAILS_ROOT}/public#{self.thumbnail(size)}"
      image_size = ImageSize.new(open(image_file).read)
      [image_size.get_width, image_size.get_height]
    rescue
      [0, 0]
    end
  end
  
  def width(size='original')
    image? && self.dimensions(size)[0]
  end
  
  def height(size='original')
    image? && self.dimensions(size)[1]
  end
  
  private
  
    def assign_title
      self.title = basename if title.blank?
    end
  
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
      attachment_options {
        :storage => :filesystem
      }
    end
  
    ##
    # Builder for AWS S3 storage
    #
    def s3_attachment_options
      attachment_options {
        :storage => :s3,
        :bucket => _c('assets.s3.bucket'),
        # :s3_host_alias => _c('assets.s3.host_alias'), # TODO add cloud front support
        :s3_credentials => {
          :access_key_id => _c('assets.s3.key'),
          :secret_access_key => _c('assets.s3.secret'),
        }
      }
    end
  
    ##
    # Builder for Rackspace CloudFiles storage
    #
    def cloud_file_attachment_options
      attachment_options {
        :storage => :cloud_file,
        :container => _c('assets.cloud_files.container'),
        :cloudfiles_credentials => {
          :username => _c('assets.cloud_files.username'),
          :api_key => _c('assets.cloud_files.api_key'),
          :servicenet => Boolean(_c('assets.cloud_files.servicenet'))
        }
      }
    end

  protected

    ##
    # The base for the builders.
    #
    # options: overrides for +has_attached_file+
    #
    def attachment_options(options = {})
      {
        # this allows us to set processors per file type, and to add more in other extensions
        :processors => lambda {|instance| instance.choose_processors },
        # and this lets extensions add thumbnailers (and also usefully defers the call)
        :styles => lambda { thumbnail_definitions },
        :whiny_thumbnails => false,
        :url => _c('assets.url') ? _c('assets.url') : "/:class/:id/:basename:no_original_style.:extension", 
        :path => _c('assets.path') ? _c('assets.path') : ":rails_root/public/:class/:id/:basename:no_original_style.:extension"
      }.merge(options)
    end
  
    alias :_c, :radiant_config
    def radiant_config( key )
      v = Radiant::Config[key] 
      v = v.strip unless v.blank? or v.strip.blank?
      return v
    end
  end
end