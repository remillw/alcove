# Time-of-day presence, in the visitor's time zone when we know it (Europe/Paris by default).
module Presence
  def self.part_of_day(time = Time.current)
    case time.hour
    when 5..11 then :morning
    when 12..17 then :afternoon
    when 18..22 then :evening
    else :night
    end
  end

  def self.now_phrase(time = Time.current) = "#{time.strftime('%A')} #{part_of_day(time)}, #{time.strftime('%H:%M')}"
end
