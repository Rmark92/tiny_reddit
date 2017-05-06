class TimeFormatter
  SECONDS_PER_MINUTE = 60
  SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
  SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR
  SECONDS_PER_MONTH = 31 * SECONDS_PER_DAY
  SECONDS_PER_YEAR = 365 * SECONDS_PER_MONTH
  UNITS_IN_SECONDS = { 'seconds' => 1,
                       'minutes' => SECONDS_PER_MINUTE,
                       'hours' => SECONDS_PER_HOUR,
                       'days' => SECONDS_PER_DAY,
                       'months' => SECONDS_PER_MONTH,
                       'years' => SECONDS_PER_YEAR }.freeze

  def self.calculate_elapsed(initial_time)
    secs = (Time.now - initial_time).to_f
    return '1 second ago' if secs < 1
    unit, count = UNITS_IN_SECONDS.map { |(unit, unit_secs)| [unit, (secs / unit_secs)] }
                                  .select { |_, count| count >= 1 }
                                  .min_by { |_, count| count }
    unit = unit[0...-1] if count.round == 1
    "#{count.round} #{unit} ago"
  end
end
