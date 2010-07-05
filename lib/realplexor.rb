require 'net/http'
require 'socket'
require "json"

class Realplexor
  include Socket::Constants
  
  class IdentifierError < StandardError; end
  class CursorError < StandardError; end

  attr_accessor :host, :port, :timeout, :identifier, :namespace, :login, :password
   
  # #This function creates a connection object and sets params for new
  # connection #Params are host, port and an additional hash for extra params.
  #
    self.port=port||80
    self.host =host||'127.0.0.1'
    self.identifier = params[:identifier]||'identifier'
    self.namespace = params[:namespace]||nil
  def initialize(host = '127.0.0.1', port = 10010, params={})
  end

  # #This function provides logon to selected server
  def logon(login, password)
    self.login = login
    self.password = password
    self.namespace = self.login + "_" + (self.namespace||'')

  end

  # #Send data
  def send_event(ids_and_cursors, data, selected_ids=nil)

    return nil if data.empty?
    data = data.to_json
    pairs = []
    ids_and_cursors.each do |value|

        id = value
        cursor = nil
      if %w{Fixnum Bignum String}.include? value.class.name
      else
        id = value[0]
        cursor = value[1]
      end
        
      raise IdentifierError, "Identifier must be alphanumeric" unless /^\w+$/ =~ id.to_s
      id = self.namespace + id.to_s if self.namespace

        throw :realplexor_error, "Cursor must be numeric" unless cursor.is_a?(Integer)
      if %w{Hash Array}.include? value.class.name
        raise CursorError, "Cursor must be numeric" unless cursor.is_a? Integer
        pairs.push(cursor.to_s+":"+id)
      else
        pairs.push(id)
      end
      if selected_ids
        selected_ids.each do |selected_id|
          pairs.push("*" + self.namespace + selected_id)
        end
      end
        
    end
    p pairs.join(',')
    dispatch(pairs.join(','), data)

  end

  def cmd_online(id_prefixes=[])
    if self.namespace
      id_prefixes.collect!{|value| self.namespace+value} if id_prefixes.empty?
    end
    resp = send_cmd("online" +(id_prefixes ? ' '+id_prefixes.join(' ') : '' ))
    return [] if resp.empty?
    resp = resp.split(',')
    if self.namespace
      prefix = Regexp.new('/^'+self.namespace+'/')
      resp.collect!{|r| r.sub!(prefix,''); r}
    end
    #      Check for removing only prefix
    return resp


  end

  def cmd_watch(from_position=0,id_prefixes=nil)
    from_position = from_position.to_i
    if self.namespace
      id_prefixes = [] unless id_prefixes
      id_prefixes.fill {|prefix| self.namespace + prefix}
    end
    resp = send_cmd("watch #{from_position}" + (id_prefixes ? " " + id_prefixes.join(" ") : "") )
    p resp
    return [] if resp.blank?
    resp = resp.split("\n")
    events = []
    resp.each do |line|
      unless (m = line.match(/^ (\w+) \s+ ([^:]+):(\S+) \s* $/sx) )
        puts "Cannot parse the event: \"#{line}\""
        next
      end
      event,pos,id = m[1], m[2], m[3]
      if from_position && self.namespace && id.rindex(self.namespace) ==0
        id.sub!(self.namespace,'')
      end
      events.push({'event'=>event, 'pos' => pos, 'id'=>id})
    end
    return events

  end

  private
  def send_cmd(cmd)
    dispatch(nil, cmd)
  end

  def dispatch(identifier, body)
    #     Build HTTP request
    headers= <<EOL
X-Realplexor: #{self.identifier}=#{ (self.login ? (self.login + ':' + self.password + '@') : '' )}#{identifier}\r\n
EOL

    p     data = <<EOL
POST / HTTP/1.1\r\nHOST: #{self.host}\r\nContent-Length: #{body.length}\r\n#{headers.chomp}\r\n#{body.chomp}
EOL
      
    sockaddr = Socket.pack_sockaddr_in( self.port, self.host)
    socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
    socket.connect(sockaddr)
    socket.write data.chomp
    socket.close_write
    results = socket.read

    unless results.empty?
      m = results.split(/\r?\n\r?\n\s*\n/s)
      r_headers, r_body = m[0], m[1]
      return [] if r_body.nil?
      if ( /^HTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)\s*(\w+)/.match(r_headers) ) or
          raise  "Headers doesn't seem correct #{r_headers.inspect}"
        if $2.to_i!=200
          raise Error, "Request failed"
        end
      end
      if (/^Content-Length: \s* (\d+)/mix.match(r_headers)) or
          raise  "Expected Content-Length in response wasn't found"
        exp_length = $1.to_i
      end
      rec_length = r_body.length
      if (exp_length != rec_length)
        raise  "The expected length and recievied body length didn't match"
      end
      r_body
      return r_body
    end
    return results

  end

end


      




  
