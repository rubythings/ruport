 require "test/helpers"
 
 begin
   require 'mocha'
   require 'stubba'
 rescue LoadError
   $stderr.puts "Warning: Mocha not found -- skipping some Query tests"
 end

 begin
   require 'dbi'
 rescue LoadError
   $stderr.puts "Warning: DBI not found -- skipping some Query tests"
 end
   
 class TestQuery < Test::Unit::TestCase
   def setup
     @sources = {
       :default => {
         :dsn => 'ruport:test',  :user => 'greg',   :password => 'apple' },
       :alternative => {
         :dsn => "ruport:test2", :user => "sandal", :password => "harmonix" },
     }
     Ruport::Query.add_source :default,     @sources[:default]
     Ruport::Query.add_source :alternative, @sources[:alternative]
 
     @columns = %w(a b c)
     @data = [ [[1,2,3],[4,5,6],[7,8,9]],
               [[9,8,7],[6,5,4],[3,2,1]],
               [[7,8,9],[4,5,6],[1,2,3]], ]
     @datasets = @data.dup
 
     @sql = [ "select * from foo", "create table foo ..." ]
     @sql << @sql.values_at(0, 0).join(";\n")
     @sql << @sql.values_at(1, 0).join(";\n")
     @query = {
      :plain      => Ruport::Query.new(@sql[0]),
      :sourced    => Ruport::Query.new(@sql[0], :source        => :alternative),
      :paramed    => Ruport::Query.new(@sql[0], :params        => [ 42 ]),
      :raw        => Ruport::Query.new(@sql[0], :row_type      => :raw),
      :resultless => Ruport::Query.new(@sql[1]),
      :multi      => Ruport::Query.new(@sql[2]),
      :mixed      => Ruport::Query.new(@sql[3]),
     }
   end

   if Object.const_defined? :Mocha and Object.const_defined? :DBI
 
     def test_execute
       query = @query[:plain]
       setup_mock_dbi(1)
 
       assert_equal nil, query.execute
     end
   
     def test_execute_sourced
       query = @query[:sourced]
       setup_mock_dbi(1, :source => :alternative)
   
       assert_equal nil, query.execute
     end
   
     def test_execute_paramed
       query = @query[:paramed]
       setup_mock_dbi(1, :params => [ 42 ])
   
       assert_equal nil, query.execute
     end
   
     def test_result_resultless
       query = @query[:resultless]
       setup_mock_dbi(1, :resultless => true, :sql => @sql[1])
   
       assert_equal nil, query.result
     end
   
     def test_result_multi
       query = @query[:multi]
       setup_mock_dbi(2)
   
       assert_equal @data[1], get_raw(query.result)
     end
   
     def test_result_raw_enabled
       query = @query[:raw]
       setup_mock_dbi(1)
       
       assert_equal @data[0], query.result
     end  
   
     def test_load_file
       File.expects(:read).
         with("query_test.sql").
         returns("select * from foo\n")
       
       query = Ruport::Query.new "query_test.sql"
       assert_equal "select * from foo", query.sql
     end      
     
     def test_explicit
       File.expects(:read).
       with("query_test").
       returns("select * from foo\n")  

       query = Ruport::Query.new(:file => "query_test")
       assert_equal "select * from foo", query.sql 
       
       query = Ruport::Query.new(:string => "query_test")
       assert_equal "query_test", query.sql       
     end
   
     def test_load_file_not_found
       File.expects(:read).
         with("query_test.sql").
         raises(Errno::ENOENT)
   
       assert_raises LoadError do
         query = Ruport::Query.new "query_test.sql"
       end
     end
   
     def test_each
       query = @query[:plain]
       setup_mock_dbi(2)
   
       result = []; query.each { |r| result << r.to_a }
       assert_equal @data[0], result
                    
       result = []; query.each { |r| result << r.to_a }
       assert_equal @data[1], result
     end  

     def test_each_multi
       query = @query[:multi]
       setup_mock_dbi(2)
   
       result = []; query.each { |r| result << r.to_a }
       assert_equal @data[1], result
     end

   end
   
   def test_each_without_block
     assert_raise (LocalJumpError) { @query[:plain].each }
   end
   
   def test_select_source
     query = @query[:plain]
     query.select_source :alternative
     assert_equal @sources[:alternative], get_query_source(query)
   
     query.select_source :default
     assert_equal @sources[:default], get_query_source(query)
   end
 
   def test_initialize_source_temporary
     query = Ruport::Query.new "<unused>", @sources[:alternative]
     assert_equal @sources[:alternative], get_query_source(query)
   end
 
   def test_initialize_source_temporary_multiple
     query1 = Ruport::Query.new "<unused>", @sources[:default]
     query2 = Ruport::Query.new "<unused>", @sources[:alternative]
     
     assert_equal @sources[:default], get_query_source(query1)
     assert_equal @sources[:alternative], get_query_source(query2)
   end
 
   if Object.const_defined? :Mocha and Object.const_defined? :DBI
 
     def test_to_table
       query = @query[:raw]
       setup_mock_dbi(3, :returns => @data[0])
   
       assert_equal @data[0], query.result
       assert_equal @data[0].to_table(@columns), query.to_table
       assert_equal @data[0], query.result
     end
   
     def test_to_csv
       query = @query[:plain]
       setup_mock_dbi(1)
       
       csv = @data[0].to_table(@columns).as(:csv)
       assert_equal csv, query.to_csv
     end
     
     def test_missing_dsn
       assert_raise(ArgumentError) {
         Ruport::Query.add_source :foo, :user => "root", :password => "fff"
       }
       assert_nothing_raised { Ruport::Query.add_source :bar, :dsn => "..." }
     end

     def test_new_defaults
       Ruport::Query.add_source :default, :dsn      => "dbi:mysql:test",
                                          :user     => "root",
                                          :password => ""
       assert_equal("dbi:mysql:test", Ruport::Query.default_source.dsn)
       assert_equal("root", Ruport::Query.default_source.user)
       assert_equal("", Ruport::Query.default_source.password)
     end

     def test_multiple_sources
       Ruport::Query.add_source :foo, :dsn => "dbi:mysql:test"
       Ruport::Query.add_source :bar, :dsn => "dbi:mysql:test2"
       assert_equal("dbi:mysql:test",  Ruport::Query.sources[:foo].dsn)
       assert_equal("dbi:mysql:test2", Ruport::Query.sources[:bar].dsn)
     end

   end
     
   private
   def setup_mock_dbi(count, options={})
     sql = options[:sql] || @sql[0]
     source = options[:source] || :default
     returns = options[:returns] || Proc.new { @datasets.shift }
     resultless = options[:resultless]
     params = options[:params] || []
     
     @dbh = mock("database_handle")
     @sth = mock("statement_handle")
     def @dbh.execute(*a, &b); execute__(*a, &b); ensure; sth__.finish if b; end
     def @sth.each; data__.each { |x| yield(x.dup) }; end
     def @sth.fetch_all; data__; end
     
     DBI.expects(:connect).
       with(*@sources[source].values_at(:dsn, :user, :password)).
       yields(@dbh).times(count)
     @dbh.expects(:execute__).with(sql, *params).
       yields(@sth).returns(@sth).times(count)
     @dbh.stubs(:sth__).returns(@sth)
     @sth.expects(:finish).with().times(count)
     unless resultless
       @sth.stubs(:fetchable?).returns(true)
       @sth.stubs(:column_names).returns(@columns)
       @sth.expects(:data__).returns(returns).times(count)
     else
       @sth.stubs(:fetchable?).returns(false)
       @sth.stubs(:column_names).returns([])
       @sth.stubs(:cancel)
       @sth.expects(:data__).times(0)
     end  
   end
   
   def get_query_source(query)
     [ :dsn, :user, :password ].inject({}) do |memo, var|
       memo.update var => query.instance_variable_get("@#{var}")
     end
   end
 
   def get_raw(table)
     table.map { |row| row.to_a }
   end
end
