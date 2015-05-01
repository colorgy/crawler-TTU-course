require 'capybara'
require 'json'
require 'pry'
require 'nokogiri'
require 'rest-client'
require 'ruby-progressbar'

DAYS = ["六", "五", "四", "三", "二", "一"]
PERIODS = ["一", "二", "三", "四", "午", "五", "六", "七", "八", "晚", "九", "十", "十一", "十二"]

class Spider
  include Capybara::DSL
  attr_accessor :courses

  def initialize
    Capybara.default_driver = :selenium
    Capybara.javascript_driver = :selenium
    @courses = {}
  end

  def parse_table(table)
    # eg. table = doc.css('table.cistab')

    rows = table.css('tr:not(:first-child)')
    rows.each_with_index do |row, periods|
      grids = row.css('td')
      grids[0..-2].each_with_index do |grid, days| # skip last
        # empty precheck
        next if grid.text.strip[0].ord == 160 && grid.text.strip.length == 1

        # course urls
        urls = grid.css('a').map {|a| "http://selquery.ttu.edu.tw/Main/#{a["href"]}"}

        # replace br for splitting
        grid.search('br').each {|n| n.replace("\n")}
        classes = grid.text.split("\n")
        classes.each {|e| classes.delete(e) if e.length == 0}

        # 看起來會長這樣，三個一組
        # [
        #   "G1511M",
        #   "英文(一)",
        #   "A8-B208",
        #   "G1511N",
        #   "英文(一)",
        #   "A8-B202"
        # ]
        0.step(classes.count-1, 3) do |i|
          # initial object
          course_code = classes[i]
          classroom = classes[i+2]
          day = DAYS[days]
          period = PERIODS[periods]

          @courses[course_code] = {} if @courses[course_code].nil?
          @courses[course_code]["code"] = course_code
          @courses[course_code]["name"] = classes[i+1]
          @courses[course_code]["url"] = urls[i/3]
          @courses[course_code]["time"] = [] if @courses[course_code]["time"].nil?
          @courses[course_code]["department"] = @dep
          @courses[course_code]["class"] = @cla

          @courses[course_code]["time"] << {
            day: day,
            period: period,
            classroom: classroom
          }
          @courses[course_code]["time"].uniq!

          #parse_syllabus(course_code)
        end
      end
    end


  end

  def crawl
    page.visit "http://selquery.ttu.edu.tw/Main/ViewClass.php"
    department_counts = page.all('select[name="SelDp"] option').count

    department_counts.times do |dep_op|
      page.visit "http://selquery.ttu.edu.tw/Main/ViewClass.php"
      department_options = page.all('select[name="SelDp"] option')
      @dep = department_options[dep_op].text
      department_options[dep_op].select_option

      class_count = page.all('select[name="SelCl"] option').count
      class_count.times do |cla_op|
        class_options = page.all('select[name="SelCl"] option')
        @cla = class_options[cla_op].text
        class_options[cla_op].select_option

        doc = Nokogiri::HTML(page.html)
        parse_table(doc.css('table.cistab')[0])

      end
    end

    return @courses
  end

  def crawl_each_syllabus
    course_codes = @courses.keys
    progressbar = ProgressBar.create(total: course_codes.count)
    course_codes.each do |code|
      parse_syllabus(code)
      progressbar.increment
    end
  end

  def parse_syllabus(course_code)
    r = RestClient.get "http://selquery.ttu.edu.tw/Main/syllabusview.php?SbjNo=#{course_code}"
    doc = Nokogiri::HTML(r.to_s)
    begin
       @courses[course_code]["textbook"] = doc.css('table.cistab > tr:contains("教科書")').first.css('td').last.text.strip
    rescue

    end
    begin
      @courses[course_code]["reference"] = doc.css('table.cistab > tr:contains("參考教材")').first.css('td').last.text.strip
    rescue

    end
  end

  def crawl_detail
    @courses = JSON.parse File.read('courses.json')
    course_codes = @courses.keys
    progressbar = ProgressBar.create(total: course_codes.count)
    course_codes.each do |code|
      parse_detail(code)
      progressbar.increment
    end
  end

  def parse_detail(course_code)
    r = RestClient.get @courses[course_code]["url"]
    doc = Nokogiri::HTML(r.to_s)

    @courses[course_code]["lecturer"] = doc.css('tr:contains("授課教師") td span').first.text
    @courses[course_code]["required"] = !(doc.css('tr:contains("選別") td').first.text.strip == '選修')
    @courses[course_code]["credits"] = Integer doc.css('tr:contains("學分數") td').first.text.strip
  end

end

spider = Spider.new
spider.crawl
File.open('courses.json', 'w') {|f| f.write(JSON.pretty_generate(spider.courses))}
spider.crawl_each_syllabus
spider.crawl_detail
File.open('courses.json', 'w') {|f| f.write(JSON.pretty_generate(spider.courses))}
