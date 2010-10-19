require 'yaml'
require 'fileutils'

class String
  def to_html; self end
end

class Array
  def to_html
    self.map { |o| o.to_html }.join("\n")
  end
end

class MOBI
  MEDIA_TYPES = {
    ".gif" => "image/gif",
    ".jpeg" => "image/jpeg",
    ".jpg" => "image/jpeg",
    ".css" => "text/css"
  }
  
  class Entity
    class InvalidEntity < StandardError; end
    attr_accessor :content
    
    VALID_ENTITIES = %w(title div p a img h1 h2 h3 h4 h5 h6 ul li)
    
    def initialize(name, *args, &block)
      raise InvalidEntity.new("#{name} not supported!") if !VALID_ENTITIES.include?(name.to_s)
      @name = name
      @class = []
      @attributes = args.empty? || !args.first.is_a?(Hash) ? {} : args.shift
      @content = args.empty? ? [] : args.shift
    end
    
    def attributes=(attributes)
      @attributes = attributes
    end
    
    def []=(key, val)
      @attributes[key] = val
    end
    
    def <<(content)
      @content << content
      self
    end
    
    def empty?
      @content.empty?
    end
    
    def to_html
      html = "<#{@name}"
      html << " " << (@attributes.to_a.map { |o| "#{o[0]}=\"#{o[1]}\"" }.join(' ')) unless @attributes.empty?
      html << " class=\"#{@class.join(' ')}\"" unless @class.empty?
      unless @content.empty?
        html << ">#{@content.to_html}</#{@name}>\n"
      else
        html << "/>\n"
      end
      html
    end
    
    # just add classes to the entity
    def method_missing(sym, *args)
      @class << sym.to_s
      self
    end
  end
  
  class Chapter
    attr_reader :file, :title
        
    def initialize(base_dir, output_dir, file)
      @beginning = false
      @entities = []
      @footnotes = []
      @file = "#{file}.html"
      source = File.join(base_dir, "source/#{file}.txt")
      process(source)
      File.open(File.join(output_dir, @file), "w+") { |f| f.puts self.to_html }
    end
    
    def to_html
      data = <<-EOS
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>#{@title}</title>
<link rel="stylesheet" href="main.css" type="text/css" />
</head>
<body>

      EOS
      data << @entities.map { |e| e.to_html }.join("\n")
      @footnotes.each do |fn|
        data << fn.to_html
        data << "\n"
      end
      data << <<-EOS


</body>
</html>
      EOS
    end
    
    private
      COMMANDS = {
        "#"[0] => :title,
        "="[0] => :header,
        "*"[0] => :ul,
        "-"[0] => :div,
        "<"[0] => :tag,
        "^"[0] => :section,    # custom kindle tag
        "!"[0] => :page_break, # custom kindle tag
        ":"[0] => :eoc,
      }
      FORMATTING = {
        %r{/([^/]+)/} => "em",
        %r{\*([^*]+)\*} => "strong",
        %r{_([\w ]+)_} => "u",
        %r{\[\+,([^\]]+)\]} => :footnote,
      }
      
      def process(source_file)
        @current_container = @entities
        File.open(source_file, "r") do |file|
          last_p = Entity.new("p")
          
          while line = file.gets
            line.rstrip!
            
            command = line[0]
            # format text first
            FORMATTING.keys.each do |re|
              if md = re.match(line)
                tag = FORMATTING[re]
                if tag.is_a?(Symbol)
                  send("process_inline_#{tag}", md, line)
                else
                  line.gsub!(md[0], "<#{tag}>#{md[1]}</#{tag}>")
                end
              end
            end
            if COMMANDS[command]
              send("process_#{COMMANDS[command]}".to_sym, line)
            else
              add_last_ul
              unless line.empty?
                last_p << line if last_p
              else
                @current_container << last_p unless last_p.empty?
                last_p = Entity.new("p")
              end
            end
          end # while file.gets
        end # File.open
      end # process
      
      def process_title(line)
        add_last_ul
        @title = line[1,100]
      end
      
      def process_header(line)
        add_last_ul
        i = 0
        while line[i,1] == "="
          i += 1
          break if i > 2
        end
        @current_container << Entity.new("h#{i}", line.gsub(/^=+ */, ''))
      end
      
      def process_ul(line)
        @last_ul ||= Entity.new("ul")
        @last_ul << Entity.new("li", line.gsub(/^\* */, ''))
      end
      
      def add_last_ul
        if @last_ul
          @current_container << @last_ul
        end
        @last_ul = nil
      end
      
      def process_eoc(line)
        @entities << Entity.new("h1", "* * *").centered
      end
      
      def process_div(line)
        if @last_div
          @current_container = @entities
          @current_container << @last_div
        else
          @last_div = Entity.new("div")
          @current_container = @last_div
          if md = line.match(/-(\.(\w+))?/)
            @last_div["class"] = md[2]
          end
        end
      end
      
      def process_tag(line)
        if md = line.match(/<(\w+)(\.(\w+))? +([^>]+)>/)
          tag = md[1]
          css_class = md[3]
          entity = Entity.new(tag)
          if md[4] # attributes
            entity.attributes = parse_attrs(md[4])
          end
          entity["class"] = css_class if css_class
          @current_container << entity
        end
      end
      
      def process_section(line)
      end
      
      def process_page_break(line)
        @current_container << Entity.new("mbp:pagebreak")
      end
      
      # process a footnote
      def process_inline_footnote(md, line)
        fn = @footnotes.size + 1
        fn_e = Entity.new("p")
        fn_e << Entity.new("a", :name => "fn-#{fn}")
        fn_e << "#{fn}. #{md[1]}"
        @footnotes << fn_e.small
        line.gsub!(md[0], "<sup><a href=\"#fn-#{fn}\">#{fn}</a></sup>")
      end
      
      # parse attributes for tag
      def parse_attrs(str)
        last_key = ""
        last_value = ""
        i = 0
        in_key = true
        in_string = false
        attributes = {}
        while c = str[i,1]
          raise "Invalid key" if c == " " and in_key
          if in_key
            if c == "="
              in_key = false
              in_string = false
            else
              last_key << c
            end
          else
            if c == '"'
              if in_string
                in_string = false
                in_key = true
                attributes[last_key] = last_value
                last_key = ""
                last_value = ""
                # skip blanks
                while str[i+1,1] == " "
                  i += 1
                end
              else
                in_string = true
              end
            else
              if !in_string and c == ' '
                in_key = true
                attributes[last_key] = last_value
                last_key = ""
                last_value = ""
                # skip blanks
                while str[i+1,1] == " "
                  i += 1
                end
              else
                last_value << c
              end
            end
          end
          i += 1
        end
        attributes
      end
  end
  
  def initialize
    @chapters = []
  end
  
  def create(base_dir)
    @base_dir = base_dir
    @config = YAML.load(File.read(File.join(base_dir, "config.yaml")))
    
    FileUtils::mkdir_p @config['output']
    
    media = []
    media.concat(Dir[File.join(base_dir, "media", "*.jpg")])
    media.concat(Dir[File.join(base_dir, "media", "*.gif")])
    media.concat(Dir[File.join(base_dir, "media", "*.css")])
    
    # create html for chapters
    chapters = @config['content']['chapters'].map do |c|
      Chapter.new(base_dir, @config['output'], c)
    end
    
    # create OPF
    File.open(File.join(@config['output'], "#{@config['name']}.opf"), "w+") { |f|
      f.puts <<-EOS
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">

<dc:title>#{@config['meta']['title']}</dc:title>
<dc:language>#{@config['meta']['language']}</dc:language>
<meta name="cover" content="My_Cover" />
<dc:identifier id="BookId" opf:scheme="ISBN">#{@config['meta']['isbn']}</dc:identifier>
<dc:creator>#{@config['meta']['creator']}</dc:creator>
<dc:publisher>#{@config['meta']['publisher']}</dc:publisher>
<dc:subject>#{@config['meta']['subject']}</dc:subject>
<dc:date>#{@config['meta']['date']}</dc:date>
<dc:description>#{@config['meta']['description']}</dc:description>

</metadata>
      EOS
      
      # manifest
      f.puts "<manifest>"
      chapters.each_with_index do |c, idx|
        f.puts "  <item id=\"item_#{idx}\" media-type=\"application/xhtml+xml\" href=\"#{c.file}\"></item>"
      end
      f.puts ""
      media.each do |m|
        f.puts "  <item id=\"#{File.basename(m)}\" media-type=\"#{MEDIA_TYPES[File.extname(m)]}\" href=\"#{File.basename(m)}\" />"
        FileUtils.cp m, @config['output']
      end
      f.puts ""
      
      # TOC & cover page
      f.puts "  <item id=\"My_Table_of_Contents\" media-type=\"application/x-dtbncx+xml\" href=\"#{@config['name']}.ncx\"/>"
      f.puts "  <item id=\"My_Cover\" media-type=\"image/gif\" href=\"cover.gif\"/>"
      f.puts "</manifest>"
      
      # spine
      f.puts "<spine toc=\"My_Table_of_Contents\">"
      chapters.each_with_index do |c, idx|
        f.puts "  <itemref idref=\"item_#{idx}\" />"
      end
      f.puts "</spine>"
      f.puts "<guide>"
      f.puts "  <reference type=\"toc\" title=\"Table of Contents\" href=\"toc.html\"></reference>"
      c0 = chapters[0]
      f.puts "  <reference type=\"text\" title=\"#{c0.title}\" href=\"#{c0.file}\"></reference>"
      f.puts "</guide>"
      f.puts "</package>"
    }
  end
end

if __FILE__ == $0
  MOBI.new.create(ENV['PWD'])
end
