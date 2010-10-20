require 'yaml'
require 'fileutils'

class String
  def to_html; self end
end

class NilClass
  def to_html; "" end
end

class Array
  def to_html
    self.map { |o| o.to_html }.join("")
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
    attr_accessor :content, :name
    
    VALID_ENTITIES = %w(title div p br a b img h1 h2 h3 h4 h5 h6 ul li)
    BLOCK_TYPE = {
      :block => %w(title div p br img h1 h2 h3 h4 h5 h6 ul li),
      :inline => %w(a b)
    }
    
    def initialize(name, *args)
      raise InvalidEntity.new("#{name} not supported!") if !VALID_ENTITIES.include?(name.to_s)
      @name = name
      @class = []
      @content = args.empty? || args.first.is_a?(Hash) ? [] : args.shift
      @attributes = args.empty? || !args.first.is_a?(Hash) ? {} : args.shift
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
      # debugger if !@content.empty? && @content[0].is_a?(Entity) && @content[0].name == "a"
      line_jump = BLOCK_TYPE[:block].include?(@name) ? "\n" : ""
      html = "<#{@name}"
      html << " " << (@attributes.to_a.map { |o| "#{o[0]}=\"#{o[1]}\"" }.join(' ')) unless @attributes.empty?
      html << " class=\"#{@class.join(' ')}\"" unless @class.empty?
      unless @content.empty?
        html << ">#{@content.to_html}</#{@name}>#{line_jump}"
      else
        html << "/>#{line_jump}"
      end
      html
    end
    
    # just add classes to the entity
    def method_missing(sym, *args)
      @class << sym.to_s
      self
    end
  end
  
  class Section
    attr_reader :id, :title
    
    def initialize(title, chapter_no, section_no)
      @title = title
      @id = "#{chapter_no}-#{section_no}"
    end
  end
  
  class Chapter
    attr_reader :file, :title, :name, :sections
        
    def initialize(number, base_dir, output_dir, file)
      @number = number
      @entities = []
      @footnotes = []
      @sections = []
      @file = "#{file}.html"
      @name = file
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
      data << "\n"
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
      FORMATTING = [
        [%r{\[@,([^\],]+)(,([^\]]+))?\]}, :link],
        [%r{\[\+,([^\]]+)\]}, :footnote],
        [%r{_([^/]+)_}, "em"],
        [%r{\*([^*]+)\*}, "strong"],
      ]
      
      def process(source_file)
        @current_container = @entities
        File.open(source_file, "r") do |file|
          last_p = Entity.new("p")
          
          while line = file.gets
            line.rstrip!
            
            command = line[0]
            # format text first
            FORMATTING.each do |re|
              while md = re[0].match(line)
                tag = re[1]
                check = re[2] ? re[2].call(md, line) : true
                next if !check
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
          break if i > 5
        end
        txt = line.gsub(/^=+ */, '')
        section = Section.new(txt, @name, @sections.size+1)
        @sections << section
        h = Entity.new("h#{i}")
        h << (Entity.new("a", :name => section.id) << "")
        h << txt
        @current_container << h
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
        fn_e << "<sup>#{fn}</sup> #{md[1]}"
        @footnotes << fn_e.small
        line.gsub!(md[0], "<sup><a href=\"#fn-#{fn}\">#{fn}</a></sup>")
      end
      
      def process_inline_link(md, line)
        a = Entity.new("a")
        a["href"] = md[1]
        a << (md[3] || md[1]).strip
        line.gsub!(md[0], a.to_html)
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
    chapter_no = 1
    chapters = @config['content']['chapters'].map do |c|
      chapter = Chapter.new(chapter_no, base_dir, @config['output'], c)
      chapter_no += 1
      chapter
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
        f.puts "  <item id=\"item_#{idx+1}\" media-type=\"application/xhtml+xml\" href=\"#{c.file}\"></item>"
      end
      f.puts "  <item id=\"item_#{chapters.size+1}\" media-type=\"application/xhtml+xml\" href=\"toc.html\"></item>"
      f.puts ""
      media.each do |m|
        f.puts "  <item id=\"#{File.basename(m)}\" media-type=\"#{MEDIA_TYPES[File.extname(m)]}\" href=\"#{File.basename(m)}\" />"
        FileUtils.cp m, @config['output']
      end
      f.puts ""
      
      # TOC & cover page
      f.puts "  <item id=\"My_Table_of_Contents\" media-type=\"application/x-dtbncx+xml\" href=\"#{@config['name']}.ncx\"/>"
      f.puts "  <item id=\"My_Cover\" media-type=\"image/gif\" href=\"cover.jpg\"/>"
      f.puts "</manifest>"
      
      # spine
      f.puts "<spine toc=\"My_Table_of_Contents\">"
      chapters.each_with_index do |c, idx|
        f.puts "  <itemref idref=\"item_#{idx+1}\" />"
      end
      f.puts "</spine>"
      f.puts "<guide>"
      f.puts "  <reference type=\"toc\" title=\"Table of Contents\" href=\"toc.html\"></reference>"
      c0 = chapters[0]
      f.puts "  <reference type=\"text\" title=\"#{c0.title}\" href=\"#{c0.file}\"></reference>"
      f.puts "</guide>"
      f.puts "</package>"
    }
    
    # create NCX (this is the TOC)
    File.open(File.join(@config['output'], "#{@config['name']}.ncx"), "w+") { |f|
      # header
      f.puts <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
	"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="en-US">
<head>
<meta name="dtb:uid" content="BookId"/>
<meta name="dtb:depth" content="2"/>
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>#{@config['meta']['title']}</text></docTitle>
<docAuthor><text>#{@config['meta']['creator']}</text></docAuthor>
  <navmap>
    <navPoint class="toc" id="toc" playOrder="1">
      <navLabel>
        <text>Table of Contents</text>
      </navLabel>
      <content src="toc.html"/>
    </navPoint>
      EOS
      
      # sections
      play_order = 1
      chapters.each_with_index do |chapter, idx|
        klass = (idx == 0) ? "welcome" : "chapter"
        f.puts <<-EOS
    <navPoint class="#{klass}" id="#{chapter.name}" playOrder="#{play_order}">
      <navLabel>
        <text>#{chapter.title}</text>
      </navLabel>
      <content src="#{chapter.file}"/>
    </navPoint>
        EOS
        play_order += 1
        chapter.sections.each_with_index do |section, sidx|
          f.puts <<-EOS
    <navPoint class="section" id="_#{section.id}" playOrder="#{play_order}">
      <navLabel>
        <text>#{section.title}</text>
      </navLabel>
      <content src="#{chapter.file}##{section.id}"/>
    </navPoint>
          EOS
          play_order += 1
        end
      end
      
      f.puts "\n</ncx>"
    }

    # create the HTML TOC
    File.open(File.join(@config['output'], "toc.html"), "w+") { |f|
      f.puts <<-EOS
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Table of Contents</title></head>
<body>

      EOS
      
      div = Entity.new("div")
      div << Entity.new("h1", "TABLE OF CONTENTS")
      div << Entity.new("br")
      chapters.each do |c|
        h3 = Entity.new("h3")
        h3 << (Entity.new("a", :href => c.file) << c.title)
        div << h3
        div << Entity.new("br")
        # sections
        
        s_div = Entity.new("div")
        ul = Entity.new("ul")
        c.sections.each do |s|
          li = Entity.new("li")
          li << (Entity.new("a", :href => "#{c.file}##{s.id}") << s.title)
          ul << li
        end
        s_div << ul
        div << s_div
        div << Entity.new("br")
      end
      div << Entity.new("h1", "* * *", :style => "text-align: center")
      f.puts div.to_html
      
      f.puts <<-EOS

</body>
</html>
      EOS
    }
  end
end

if __FILE__ == $0
  MOBI.new.create(ENV['PWD'])
end
