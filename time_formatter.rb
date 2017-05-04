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
    secs_passed = (Time.now - initial_time).to_f
    unit_to_use, unit_count = if secs_passed < 1
                                ['seconds', 1]
                              else
                                UNITS_IN_SECONDS.map { |(unit, num_secs)| [unit, (secs_passed / num_secs)] }
                                                .select { |unit, count| count >= 1 }
                                                .min_by { |_, count| count }
                              end
    unit_to_use = unit_to_use[0...-1] if unit_count.round == 1
    "#{unit_count.round} #{unit_to_use} ago"
  end
end
