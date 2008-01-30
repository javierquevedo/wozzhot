class SearchController < ApplicationController

  def query
  end

  def results
  @tag = Tag.find_by_id(params[:tag])
  end
end
