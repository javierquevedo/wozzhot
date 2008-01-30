class BuildController < ApplicationController
  require 'thread'
 
  def query
  end
  
  def hotnow
 
    #render :xml => output.to_xml
    
    tagstats = Tagstat.find(:all);
    tagstats.sort! {|x,y| y.karma <=> x.karma }
    render :xml => tagstats[0 .. 20].to_xml
    
  end
  
  def intermediate
    
     query=params[:tag][:title]
     redirect_to :controller => 'build', :action =>'results', :query  => query
     
  end

  def parse(query)
    #cleanup_database
    
    time_to_next_search = 1.week
    
    clean_query(query)
    
    @tag = Tag.find_by_title(query)
   
    semaphore = Mutex.new          
    
    if !@tag
      @tag=Tag.new(:title => query)
      parse_services(semaphore)
      
    else
      if (@tag.updated_at + time_to_next_search) < Time.now 
        Item.destroy(@tag.items)   
        #items = @tag.items
        #Item.delete_all(items)
        Tag.destroy(@tag)
        @tag = Tag.new(:title => query)
        parse_services(semaphore)
      end
    end
    
    #render :update do |page|
    #    page.insert_html :top,:youtube_results, :partial => 'tag', :object => @tag
    #end
    #redirect_to :controller => 'build', :action => 'results', :tag => @tag.title
    #xml = Xml.new
    #xml << @tag.to_s #&& 
    #xml << @tag.items
    #
   #respond_to do |format|
   #   format.html
   render :xml => @tag.items.to_xml
   #end

   # render :xml => @tag.items.to_xml
    updatestats(query)
      
  
  end

  def results
    @available_categories = ["flickr","youtube", "lastfm", "delicious", "technorati"]
    parse(params[:query])
    
    
    
    
    #@tag = Tag.find_by_title(params[:tag])
      #redirect_to home_path 
      #:controller => 'build', :action => 'query'
    
    
  end

  private
  
  def updatestats(query)
      for elem in Tagstat.find(:all)
       elem.karma-=1;
       if (elem.karma < 1)
         Tagstat.destroy(elem);
       else
       elem.save
       end  
      end 
   tagstat = Tagstat.find_by_title(query)
    if !tagstat
      tagstat = Tagstat.new(:title => query, :karma => 100);  
      tagstat.save;
    else
      tagstat.karma +=75;
      tagstat.save;
    end
   
  end
  
  def builditem (url, title, description, thumbnail, category, tag)
    #CREATE AN ITEM
    #If the item doesn't exist we create a new one
    #else we we associate the item with the tag
    found=Item.find_by_url(url)       
    if !found
      tag.items.build(
        :title => title, 
        :url => url,
        :description => description,
        :thumbnail => thumbnail,
        :category => category
      )
    else
      if !tag.items.exists?(:url => url)
        tag.items<<found
      end
    end 
  end
  
  
  def builditems (urls, titles, descriptions, thumbnails, category, tag)        
    #CREATE EACH ITEM
    
    urls.each_index do |index|
      builditem(
        urls[index],
        titles[index],
        descriptions[index],
        thumbnails[index],
        category, 
        tag)
     
    end
    tag.save
  end
  
  def parser (
      tag,
      url, 
      category, 
      title_node,
      title_attribute,
      link_node, 
      link_attribute,
      description_node, 
      description_attribute,
      thumbnail_node,
      thumbnail_attribute,
      semaphore
    )
      
    xml_data = Net::HTTP.get_response(URI.parse(url)).body
    doc = REXML::Document.new(xml_data)


    links = Array.new
    titles = Array.new
    descriptions = Array.new
    thumbnails = Array.new if thumbnail_node
    #Get the titles, urls and descriptions
    doc.elements.each(title_node) do |ele|
      if !title_attribute
        titles << ele.text
      else
        titles << ele.attributes[title_attribute]
      end
    end

    doc.elements.each(link_node) do |ele|
      if !link_attribute
        links << ele.text
      else
        links << ele.attributes[link_attribute]
      end
    end

    doc.elements.each(description_node) do |ele|
      if !description_attribute
        descriptions << ele.text
      else
        descriptions << ele.attributes[description_attribute]
      end
    end
    
    if thumbnail_node
      doc.elements.each(thumbnail_node) do |ele|
        if !thumbnail_attribute
          thumbnails << ele.text
        else
          thumbnails << ele.attributes[thumbnail_attribute]
        end
      end
    else
      thumbnails = Array.new(links.size)
    end

    
    semaphore.synchronize{
      builditems(links, titles, descriptions, thumbnails, category, tag)    
    }
  end

  def parse_lastfm(semaphore)
      
    parser(
      @tag,
      'http://ws.audioscrobbler.com/1.0/tag/' + @tag.title + '/topartists.xml',
      'lastfm',
      'tag/artist/', #title_node
      'name',
      'tag/artist/url', #link_node
      nil, #link_attribute
      'tag/artist/mbid', #description_node
      nil, #description_attribute
      'tag/artist/thumbnail', # no thumbnail for delicious
      nil, #thumbnail_attribute
      semaphore
    )
     

  end
  
  def parse_youtube(semaphore)
    query = String.new(@tag.title)
    if query.count('+') > 0
    query.gsub!("+", "/")
    
    end
    
    
    parser(
      @tag,
      'http://gdata.youtube.com/feeds/api/videos/-/' + query,
      'youtube',
      '/feed/entry/title',
      nil,
      '/feed/entry/media:group/media:player',
      'url',
      '/feed/entry/media:group/media:description',
      nil,
      nil,
      nil,
      semaphore
    )
     
  end

  def parse_delicious(semaphore)
    query = @tag.title
    if query.count('+') == 0
      url = 'http://del.icio.us/rss/popular/' + @tag.title
    else
      url = 'http://del.icio.us/rss/tag/' + @tag.title
    
    end
    
    parser(
      @tag,
      url,
      'delicious',
      '/rdf:RDF/item/title', #title_node
      nil, #title_attribute
      '/rdf:RDF/item/link', #link_node
      nil, #link_attribute
      '/rdf:RDF/item/dc:creator', #description_node)
      nil, #description_attribute
      nil,      # no thumbnail for delicious
      nil, #no thumbnail_attribute
      semaphore
    )  
    
  
  end
  
  def parse_technorati(semaphore)
    #Technorati
    parser(
    @tag,
    'http://feeds.technorati.com/tag/' + @tag.title,
    'technorati',
    'rss/channel/item/title',
    nil,
    'rss/channel/item/link',
    nil,
    'rss/channel/item/description',
    nil,
    nil,
    nil,
    semaphore
    )
  end
  
  def parse_flickr(semaphore)
    #Flickr
    parser(
    @tag,
    'http://api.flickr.com/services/feeds/photos_public.gne?tags=' +  @tag.title + '&lang=en-us&format=rss_200',
    'flickr',
    'rss/channel/item/title',
    nil,
    'rss/channel/item/link',
    nil,
    'rss/channel/item/description',
    nil,
    'rss/channel/item/media:thumbnail',
    'url',
    semaphore
     )
  end
    
  def parse_services(semaphore)
      
    #lfmthread=Thread.new do
        #  parse_lastfm(semaphore)
        
    #    lfmthread.exit
     # end 
     if  params[:yt]=='true' 
     ytthread=Thread.new do
          parse_youtube(semaphore)
     #   ytthread.exit
      end 
     end
     
      if  params[:dc]=='true'
      dcthread=Thread.new do
           parse_delicious(semaphore)
      end
      end
      
      if  params[:tc]=='true'
      tcthread=Thread.new do
          parse_technorati(semaphore)
      end
      end
      
      if  params[:fl]=='true'
      flthread=Thread.new do
        parse_flickr(semaphore)
      end
      end
      
      #if lfmthread.alive?
      #  lfmthread.join    
      #end
    
      if params[:yt]=='true' and ytthread.alive? 
        ytthread.join
      end
    
      if params[:dc]=='true' and dcthread.alive?
        dcthread.join
      end
      
      if params[:tc]=='true' and tcthread.alive?
        tcthread.join
      end
      
      if params[:fl]=='true' and flthread.alive?
        flthread.join
      end
      
      
    
    
    
  end

  def clean_query(query)
    
#query.delete! ","
#query.delete! "."
query.delete! ";"
query.delete! ":"
query.delete! "-"
query.delete! "!"
query.delete! "?"
query.delete! '"'
query.delete! "\n"
query.delete! "\r"
query.gsub!("\ ", "+")



    
  end


  def cleanup_database
    
    for tag in Tag.find(:all)
      Item.destroy(tag.items)
      Tag.destroy(tag)
      
    end
   
  end
end
  
