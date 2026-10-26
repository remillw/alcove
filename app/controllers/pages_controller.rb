class PagesController < ApplicationController
  allow_unauthenticated_access

  def legal = resume_session
  def terms = resume_session
  def privacy = resume_session
end
