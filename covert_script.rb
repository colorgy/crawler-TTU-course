# covert ttu courses to right way
require 'json'
require 'pry'

deps = JSON.parse(File.read('ttu_code.json'));
courses = JSON.parse(File.read('courses.json'));

courses.each do |k, course|
  deps.each do |k, v|
    v.reverse_each do |dep|
      if course["class"].include?(dep["department"])
        # binding.pry
        course["department_code"] = dep["code"]
        break
      end
    end
  end
end

File.open('ttu_courses.json', 'w' ) {|f| f.write(JSON.pretty_generate(courses.map {|k, v| v}))}