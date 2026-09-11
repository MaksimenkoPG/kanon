# frozen_string_literal: true

# Measurements quoted in README.md.
# No framework needed: ruby -Ilib script/benchmark.rb from the repository root.
#
# The configs are generated into a temporary directory, so the numbers describe
# the machinery itself and do not depend on any application.
require 'benchmark'
require 'objspace'
require 'tmpdir'
require 'kanon'

ROUNDS = 7
READS = 100_000
SERVICES = 11

def write_configs(directory)
  services = (1..SERVICES).map do |index|
    <<~YAML
      #{'  ' * 2}:service_#{index}:
      #{'  ' * 3}:url: { env: SERVICE_#{index}_URL }
      #{'  ' * 3}:key: { env: SERVICE_#{index}_KEY }
      #{'  ' * 3}:access_id: { env: SERVICE_#{index}_ACCESS_ID }
    YAML
  end

  File.write(File.join(directory, 'wide.yml'), <<~YAML)
    default: &default
      :wide:
    #{services.join}
    production:
      <<: *default
  YAML

  File.write(File.join(directory, 'nested.yml'), <<~YAML)
    default: &default
      :nested:
        :credentials:
          :access_key_id: { env: STORAGE_ACCESS_KEY_ID, default: '' }
          :secret_access_key: { env: STORAGE_SECRET_ACCESS_KEY, default: '' }
          :dualstack: { default: false }
        :buckets:
          :private:
            :name: { env: PRIVATE_BUCKET }
            :region: { default: eu-west-1 }
          :public:
            :name: { env: PUBLIC_BUCKET }
            :region: { default: eu-west-1 }
          :archive:
            :name: { env: ARCHIVE_BUCKET }
            :region: { default: us-east-1 }

    production:
      <<: *default
  YAML
end

def fill_environment
  (1..SERVICES).each do |index|
    %w[URL KEY ACCESS_ID].each { |suffix| ENV["SERVICE_#{index}_#{suffix}"] = "value-#{index}-#{suffix}" }
  end
  %w[PRIVATE_BUCKET PUBLIC_BUCKET ARCHIVE_BUCKET].each { |name| ENV[name] = name.downcase }
end

def best_of(rounds)
  Array.new(rounds) do
    GC.start
    yield
  end.min
end

def deep_size(object, seen = {}.compare_by_identity)
  return 0 if seen[object]

  seen[object] = true
  size = ObjectSpace.memsize_of(object)
  case object
  when Hash then object.each { |key, value| size += deep_size(key, seen) + deep_size(value, seen) }
  when Array then object.each { |value| size += deep_size(value, seen) }
  end
  size
end

def count_nodes(node)
  return 0 unless node.is_a?(Kanon::Node)

  1 + node.keys.sum { |key| count_nodes(node[key]) }
end

CONFIGS = %i[wide nested].freeze

def report_reads(nodes)
  node = nodes[:nested]
  hash = node.to_h
  cases = {
    'plain hash: HASH[:buckets][:private][:name]' => -> { hash[:buckets][:private][:name] },
    'node at hand: node.buckets.private.name' => -> { node.buckets.private.name },
    'full path: Kanon[...].buckets...name' => -> { Kanon[:nested].buckets.private.name },
    'cache lookup only: Kanon[:nested]' => -> { Kanon[:nested] }
  }

  puts '=== One value read, best of seven rounds ==='
  timings = cases.map do |label, block|
    micros = best_of(ROUNDS) { Benchmark.realtime { READS.times { block.call } } / READS * 1_000_000 }
    puts format('  %<label>-44s %<micros>7.3f us', label: label, micros: micros)
    micros
  end
  puts format('  node vs hash %<node>.1fx, full path vs hash %<full>.1fx',
              node: timings[1] / timings[0], full: timings[2] / timings[0])
end

def report_warm_up
  boot = best_of(ROUNDS) do
    Benchmark.realtime do
      50.times do
        Kanon.send(:clear)
        Kanon.load_configs(*CONFIGS)
      end
    end / 50 * 1000
  end

  puts '=== Warm-up ==='
  puts format('  load_configs(%<count>d files): %<boot>.2f ms', count: CONFIGS.size, boot: boot)
end

def report_to_h(nodes)
  puts '=== to_h ==='
  CONFIGS.each do |name|
    micros = best_of(ROUNDS) { Benchmark.realtime { 20_000.times { nodes[name].to_h } } / 20_000 * 1_000_000 }
    puts format('  %<name>-20s %<micros>6.1f us', name: name, micros: micros)
  end
end

def report_memory(nodes)
  puts '=== Memory ==='
  totals = CONFIGS.map do |name|
    hash_bytes = deep_size(nodes[name].to_h)
    node_bytes = hash_bytes + (count_nodes(nodes[name]) * ObjectSpace.memsize_of(nodes[name]))
    puts format('  %<name>-20s tree %<node>6d B, hash %<hash>6d B', name: name, node: node_bytes, hash: hash_bytes)
    [node_bytes, hash_bytes]
  end
  puts format('  %<name>-20s tree %<node>6d B, hash %<hash>6d B',
              name: 'TOTAL', node: totals.sum(&:first), hash: totals.sum(&:last))
  puts format('  objects allocated by 100 reads of the wider config: %<count>d', count: allocations_of_reads)
end

def allocations_of_reads
  GC.start
  GC.disable
  before = GC.stat[:total_allocated_objects]
  kept = Array.new(100) { Kanon.read_config(:wide) }
  allocated = GC.stat[:total_allocated_objects] - before
  GC.enable
  kept.clear
  allocated
end

Dir.mktmpdir('kanon_benchmark') do |directory|
  write_configs(directory)
  fill_environment
  Kanon.directory = directory
  Kanon.environment = 'production'

  nodes = Kanon.load_configs(*CONFIGS)
  report_reads(nodes)
  puts
  report_warm_up
  puts
  report_to_h(nodes)
  puts
  Kanon.send(:clear)
  report_memory(Kanon.load_configs(*CONFIGS))
end

puts
puts "ruby #{RUBY_VERSION}, psych #{Psych::VERSION}"
