# frozen_string_literal: true

require 'date'

# Parser for vCard (VCF) files.
# Supports vCard 3.0 and 4.0 for import/export of contact data.
module VcfParser
  # Parses a vCard file and returns array of contact hashes.
  # Each contact hash has keys matching Person metadata fields.
  def self.parse_file(filepath)
    content = File.read(filepath)
    parse(content)
  end

  # Parses vCard content string and returns array of contact hashes.
  def self.parse(content)
    contacts = []
    current_card = nil

    # Unfold continued lines (lines starting with space/tab are continuation)
    content = content.gsub(/\r\n[ \t]/, '').gsub(/\n[ \t]/, '')

    content.each_line do |line|
      line = line.strip
      next if line.empty?

      case line
      when /^BEGIN:VCARD/i
        current_card = {}
      when /^END:VCARD/i
        contacts << normalize_contact(current_card) if current_card
        current_card = nil
      else
        parse_property(line, current_card) if current_card
      end
    end

    contacts
  end

  # Parses a single vCard property line.
  def self.parse_property(line, card)
    # Split on first colon (property:value)
    return unless line.include?(':')

    prop_part, value = line.split(':', 2)
    return if value.nil?

    # Parse property name and parameters
    parts = prop_part.split(';')
    property = parts.first.upcase
    params = parse_params(parts[1..])

    case property
    when 'FN'
      card[:full_name] = unescape(value)
    when 'N'
      # N:Last;First;Middle;Prefix;Suffix
      name_parts = value.split(';')
      card[:name_parts] = {
        last: unescape(name_parts[0]),
        first: unescape(name_parts[1]),
        middle: unescape(name_parts[2]),
        prefix: unescape(name_parts[3]),
        suffix: unescape(name_parts[4])
      }
    when 'EMAIL'
      card[:emails] ||= []
      card[:emails] << unescape(value)
    when 'TEL'
      card[:phones] ||= []
      phone_entry = { number: unescape(value), type: params['TYPE'] }
      card[:phones] << phone_entry
    when 'ORG'
      card[:organization] = unescape(value.split(';').first)
    when 'TITLE'
      card[:role] = unescape(value)
    when 'BDAY'
      card[:birthday] = parse_date(value)
    when 'ADR'
      # ADR:;;Street;City;State;Zip;Country
      addr_parts = value.split(';')
      card[:address] = [
        addr_parts[2], # Street
        [addr_parts[3], addr_parts[4], addr_parts[5]].compact.reject(&:empty?).join(', '), # City, State, Zip
        addr_parts[6] # Country
      ].compact.reject(&:empty?).join("\n")
    when 'URL'
      card[:website] = unescape(value)
    when 'NOTE'
      card[:notes] = unescape(value)
    when 'X-SOCIALPROFILE', 'X-SOCIAL'
      card[:social] ||= {}
      type = params['TYPE']&.downcase || 'other'
      card[:social][type.to_sym] = unescape(value)
    when 'X-TWITTER'
      card[:social] ||= {}
      card[:social][:twitter] = unescape(value)
    when 'X-GITHUB'
      card[:social] ||= {}
      card[:social][:github] = unescape(value)
    when 'X-LINKEDIN'
      card[:social] ||= {}
      card[:social][:linkedin] = unescape(value)
    when 'CATEGORIES'
      card[:tags] = value.split(',').map { |t| unescape(t.strip) }
    end
  end

  # Parses property parameters (e.g., TYPE=HOME).
  def self.parse_params(param_strings)
    params = {}
    return params if param_strings.nil?

    param_strings.each do |param|
      if param.include?('=')
        key, value = param.split('=', 2)
        params[key.upcase] = value
      else
        # Bare parameter like "HOME" is equivalent to TYPE=HOME
        params['TYPE'] = param
      end
    end
    params
  end

  # Normalizes a parsed contact card to match Person metadata structure.
  def self.normalize_contact(card)
    full_name = card[:full_name]

    # Build full name from N if FN not present
    if full_name.to_s.empty? && card[:name_parts]
      parts = card[:name_parts]
      full_name = [parts[:prefix], parts[:first], parts[:middle], parts[:last], parts[:suffix]]
                  .compact.reject(&:empty?).join(' ')
    end

    {
      full_name: full_name,
      emails: card[:emails] || [],
      phones: (card[:phones] || []).map { |p| p[:number] },
      organization: card[:organization],
      role: card[:role],
      birthday: card[:birthday],
      address: card[:address],
      website: card[:website],
      social: card[:social] || {},
      notes: card[:notes],
      tags: card[:tags] || []
    }
  end

  # Unescapes vCard special characters.
  def self.unescape(value)
    return nil if value.nil?

    value.to_s
         .gsub('\\n', "\n")
         .gsub('\\,', ',')
         .gsub('\\;', ';')
         .gsub('\\\\', '\\')
  end

  # Escapes special characters for vCard.
  def self.escape(value)
    return '' if value.nil?

    value.to_s
         .gsub('\\', '\\\\')
         .gsub(',', '\\,')
         .gsub(';', '\\;')
         .gsub("\n", '\\n')
  end

  # Parses various date formats to YYYY-MM-DD.
  def self.parse_date(value)
    return nil if value.to_s.empty?

    # Try ISO format first (YYYY-MM-DD or YYYYMMDD)
    if value =~ /^(\d{4})-?(\d{2})-?(\d{2})$/
      return "#{Regexp.last_match(1)}-#{Regexp.last_match(2)}-#{Regexp.last_match(3)}"
    end

    # Try to parse with Ruby's Date
    Date.parse(value).strftime('%Y-%m-%d')
  rescue ArgumentError
    value
  end

  # Converts a contact hash to vCard 4.0 format.
  def self.to_vcard(contact, version: '4.0')
    lines = []
    lines << 'BEGIN:VCARD'
    lines << "VERSION:#{version}"

    # FN (required)
    full_name = contact[:full_name] || contact[:title] || 'Unknown'
    lines << "FN:#{escape(full_name)}"

    # N (structured name)
    name_parts = full_name.split
    if name_parts.size >= 2
      first = name_parts[0..-2].join(' ')
      last = name_parts.last
      lines << "N:#{escape(last)};#{escape(first)};;;"
    else
      lines << "N:#{escape(full_name)};;;;"
    end

    # EMAIL
    Array(contact[:emails] || contact[:email]).each do |email|
      next if email.to_s.empty?

      lines << "EMAIL:#{escape(email)}"
    end

    # TEL
    Array(contact[:phones] || contact[:phone]).each do |phone|
      next if phone.to_s.empty?

      lines << "TEL:#{escape(phone)}"
    end

    # ORG
    org = contact[:organization]
    lines << "ORG:#{escape(org)}" unless org.to_s.empty?

    # TITLE (role)
    role = contact[:role]
    lines << "TITLE:#{escape(role)}" unless role.to_s.empty?

    # BDAY
    bday = contact[:birthday]
    lines << "BDAY:#{bday.to_s.delete('-')}" unless bday.to_s.empty?

    # ADR
    addr = contact[:address]
    unless addr.to_s.empty?
      # Simple format: just put in street field
      lines << "ADR:;;#{escape(addr)};;;;"
    end

    # URL
    url = contact[:website]
    lines << "URL:#{escape(url)}" unless url.to_s.empty?

    # NOTE
    notes = contact[:notes]
    lines << "NOTE:#{escape(notes)}" unless notes.to_s.empty?

    # Social profiles
    social = contact[:social] || {}
    lines << "X-TWITTER:#{escape(social[:twitter])}" if social[:twitter]
    lines << "X-GITHUB:#{escape(social[:github])}" if social[:github]
    lines << "X-LINKEDIN:#{escape(social[:linkedin])}" if social[:linkedin]

    # CATEGORIES (tags)
    tags = Array(contact[:tags])
    lines << "CATEGORIES:#{tags.map { |t| escape(t) }.join(',')}" unless tags.empty?

    lines << 'END:VCARD'
    lines.join("\r\n")
  end
end
