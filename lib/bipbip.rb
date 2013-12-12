module Bipbip
  require 'rubygems'  # For ruby < 1.9

  require 'copperegg'
  require 'yaml'
  require 'json/pure'
  require 'logger'
  require 'socket'

  require 'bipbip/version'
  require 'bipbip/helper'
  require 'bipbip/interruptible_sleep'
  require 'bipbip/agent'
  require 'bipbip/storage'
  require 'bipbip/plugin'
  require 'bipbip/service'

  def self.logger
    @logger || Logger.new(STDOUT)
  end

  def self.logger=(logger)
    @logger = logger
  end

  def self.fqdn
    @fqdn ||= Socket.gethostbyname(Socket.gethostname).first
  end
end
