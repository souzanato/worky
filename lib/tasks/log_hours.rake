namespace :log do
  desc "Analisa development.log e estima horas de trabalho por dia"
  task hours: :environment do
    logfile = "log/development.log"
    sessions = Hash.new { |h, k| h[k] = [] }

    unless File.exist?(logfile)
      puts "Arquivo #{logfile} não encontrado"
      exit
    end

    File.foreach(logfile, mode: "r:bom|utf-8") do |line|
      line = line.scrub # limpa caracteres inválidos
      if line =~ /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/
        timestamp = Time.parse($1)
        day = timestamp.strftime("%Y-%m-%d")
        sessions[day] << timestamp
      end
    end

    grand_total = 0.0

    sessions.sort.each do |day, times|
      times.sort!
      # detecta sessões (pausa > 1h quebra em nova sessão)
      grouped = []
      current = [ times.first ]

      times.each_cons(2) do |a, b|
        if (b - a) > 3600 # mais de 1h sem log
          current << a
          grouped << current
          current = [ b ]
        end
      end

      current << times.last
      grouped << current

      total_hours = 0

      puts "\n📅 #{day}"
      grouped.each_with_index do |(start_time, end_time), i|
        duration = ((end_time - start_time) / 3600).round(2)
        total_hours += duration
        puts "  Sessão #{i+1}: #{start_time.strftime("%H:%M")} → #{end_time.strftime("%H:%M")} (~#{duration}h)"
      end

      grand_total += total_hours
      puts "  Total do dia: ~#{total_hours.round(2)}h"
    end

    puts "\n====================================="
    puts "⏱️  Total geral estimado: ~#{grand_total.round(2)}h"
    puts "====================================="
  end
end
