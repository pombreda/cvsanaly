class WelcomeController < ApplicationController
  protect_from_forgery
  before_filter :authenticate_user!
  layout 'flatly'

  def home
  end

  def files_history
    @files = FileScm.joins(:type).where("type <> 'unknown'").order("file_name DESC")
  end

  def loc_by_rev
    @commits = Commit.all(:select => "scmlog.rev, scmlog.committer_id, scmlog.date, SUM(metrics.loc) AS loc_sum", :joins => :metrics, :group => "metrics.commit_id", :order => "scmlog.date")
  end

  ## LOC/SLOC SUM in time
  def loc_sum_by_date
    set_defaults
    @commiters = ['All'].concat(Person.all.collect{|person| [person.name, person.id]})
  end

  def loc_sum_by_date_filtered
    from = "#{params[:filter]['from(1i)']}-#{params[:filter]['from(2i)']}-#{params[:filter]['from(3i)']}"
    to = "#{params[:filter]['to(1i)']}-#{params[:filter]['to(2i)']}-#{params[:filter]['to(3i)']}"
    committer = params[:filter][:commiter]
    repository = params[:filter][:repository]

    conditions = "DATE(scmlog.date) between DATE('#{from}') and DATE('#{to}') AND scmlog.repository_id=#{repository}"
    conditions += "and scmlog.committer_id='#{committer}'" unless committer.eql?('All')

    @commits = Commit.all(:select => "DATE(scmlog.date) as date, SUM(metrics.loc) AS loc, SUM(metrics.sloc) AS sloc", :joins => :metrics, :group => "DATE(scmlog.date)", :conditions => conditions, :order => "DATE(scmlog.date)")

    # Add Column Headers
    data_table = GoogleVisualr::DataTable.new
    data_table.new_column('string', 'Date' )
    data_table.new_column('number', 'LOC')
    data_table.new_column('number', 'SLOC')

    rows = []
    @commits.each do |commit|
      rows.push([commit.date.strftime("%Y-%m-%d"), commit.loc, commit.sloc])
    end

    # Add Rows and Values
    data_table.add_rows(rows)
    @chart = Chart.area_chart('LOC/SLOC in time', 1024, 600, data_table)

    if @commits.any?
      render :layout => false
    else
      render :text => "No results were found."
    end
  end
  #######################

  ## Bad Smell by SLOC
  def bad_smell_by_sloc
    @repositories = Repository.all.collect{|repository| [repository.name, repository.id]}
  end

  def bad_smell_by_sloc_filtered
    repository = params[:filter][:repository]
    limit = params[:filter][:limit]
    @files = FileScm.joins(:metrics).where("repository_id=#{repository} AND lang='java' AND sloc > #{limit}").group("file_id")

    if @files.any?
      render :layout => false
    else
      render :text => "No results were found."
    end
  end
  ####################

  ## Bad Smell by Number of Methods
  def bad_smell_by_nfunctions
    @repositories = Repository.all.collect{|repository| [repository.name, repository.id]}
  end

  def bad_smell_by_nfunctions_filtered
    repository = params[:filter][:repository]
    limit = params[:filter][:limit]
    @files = FileScm.joins(:metrics).where("repository_id=#{repository} AND lang='java' AND nfunctions > #{limit}").group("file_id")
    
    if @files.any?
      render :layout => false
    else
      render :text => "No results were found."  
    end
  end
  ####################

  ## Metrics Evolution by Branch in time
  def metrics_evolution
    @repositories = Repository.all.collect{|repository| [repository.name, repository.id]}
    repository = Repository.find(@repositories.first[1])
    @branches =  Branch.branches_by_repository(repository).collect{|branch| [branch.name, branch.id]}
    set_dates(@repositories.first[1])
    @from += 1.month
    @types = ['All', 'LOC', 'SLOC', 'Files']
  end

  def metrics_evolution_filtered
    from = "#{params[:filter]['from(1i)']}-#{params[:filter]['from(2i)']}-01}"
    to = "#{params[:filter]['to(1i)']}-#{params[:filter]['to(2i)']}-01}"
    repository = params[:filter][:repository]
    branch = params[:filter][:branch]
    @type = params[:filter][:type]

    conditions = "DATE(date) between DATE('#{from}') and DATE('#{to}')"

    title = 'Metrics Evolution by Branch in time'
    if params[:filter][:branch] && !params[:filter][:branch].eql?("All")
      branch = Branch.find(params[:filter][:branch])
      title += " for branch #{branch.name}"
      conditions += " AND branch_id = #{branch.id}"
    else
      repository = Repository.find(params[:filter][:repository])
      branches =  Branch.branches_by_repository(repository).collect{|branch| branch.id}
      conditions += " AND branch_id IN (#{branches.join(',')})"
    end

    @metrics_evo = MetricsEvo.all(:select => "DATE(date) as date, branch_id, files, loc, sloc", :conditions => conditions, :order => "DATE(date)")

    # Add Column Headers
    data_table = GoogleVisualr::DataTable.new
    data_table.new_column('string', 'Date' )
    data_table.new_column('number', 'LOC')    if ['All','LOC'].include?(@type)
    data_table.new_column('number', 'SLOC')   if ['All','SLOC'].include?(@type)
    data_table.new_column('number', 'Files')  if ['All','Files'].include?(@type)

    rows = []
    @metrics_evo.each do |metric_evo|
      row = Array.new
      row.push(metric_evo.date.strftime("%Y-%m-%d"))
      row.push(metric_evo.loc)    if ['All','LOC'].include?(@type)
      row.push(metric_evo.sloc)   if ['All','SLOC'].include?(@type)
      row.push(metric_evo.files)  if ['All','Files'].include?(@type)
      rows.push(row)
    end

    # Add Rows and Values
    data_table.add_rows(rows)
    @chart = Chart.area_chart(title, 1024, 600, data_table)
    
    if @metrics_evo.any?
      render :layout => false
    else
      render :text => "No results were found."
    end
  end

  ## SUM of files modified in time
  def modifications_amount_by_commit
    set_defaults
    @modifications = {"All" => "all"}.merge(Action::TYPES)
  end

  def modifications_amount_by_commit_filtered
    from = "#{params[:filter]['from(1i)']}-#{params[:filter]['from(2i)']}-#{params[:filter]['from(3i)']}"
    to = "#{params[:filter]['to(1i)']}-#{params[:filter]['to(2i)']}-#{params[:filter]['to(3i)']}"
    modification = params[:filter][:modification]
    repository = params[:filter][:repository]

    conditions = "DATE(scmlog.date) between DATE('#{from}') and DATE('#{to}') AND scmlog.repository_id=#{repository}"
    conditions += "AND actions.type='#{modification}'" unless modification.eql?('all')

    @commits = Commit.all(:select => "scmlog.rev, scmlog.committer_id, DATE(scmlog.date) as date, COUNT(*) AS sum, actions.type", :joins => :actions, :group => "DATE(scmlog.date), type", :conditions => conditions, :order => "DATE(scmlog.date) ASC")

    @commits_hash = Hash.new()
    @commits.each do |commit|
      @commits_hash[commit.date.strftime("%Y-%m-%d")] = Hash.new() unless @commits_hash[commit.date.strftime("%Y-%m-%d")]
      @commits_hash[commit.date.strftime("%Y-%m-%d")][commit.type] = commit.sum
    end

    data_table = GoogleVisualr::DataTable.new

    # Add Column Headers
    data_table.new_column('string', 'Date' )
    data_table.new_column('number', 'Added')    if ['all','A'].include?(modification)
    data_table.new_column('number', 'Modified') if ['all','M'].include?(modification)
    data_table.new_column('number', 'Deleted')  if ['all','D'].include?(modification)
    data_table.new_column('number', 'Renamed')  if ['all','V'].include?(modification)
    data_table.new_column('number', 'Copied')   if ['all','C'].include?(modification)
    data_table.new_column('number', 'Replaced') if ['all','R'].include?(modification)

    rows = []
    @commits_hash.each_pair do |key, value|
      row = Array.new()
      row.push(key)
      row.push(value['A'].nil? ? 0 : value['A']) if ['all','A'].include?(modification)
      row.push(value['M'].nil? ? 0 : value['M']) if ['all','M'].include?(modification)
      row.push(value['D'].nil? ? 0 : value['D']) if ['all','D'].include?(modification)
      row.push(value['V'].nil? ? 0 : value['V']) if ['all','V'].include?(modification)
      row.push(value['C'].nil? ? 0 : value['C']) if ['all','C'].include?(modification)
      row.push(value['R'].nil? ? 0 : value['R']) if ['all','R'].include?(modification)
      rows.push(row)
    end

    # Add Rows and Values
    data_table.add_rows(rows)
    @chart = Chart.area_chart('SUM of Files Modified in time', 1024, 600, data_table)

    if @commits_hash.any?
      render :layout => false
    else
      render :text => "No results were found."
    end
  end
  ################################

  def commit_lines_graph
    @commits_lines = CommitsLine.all(:select => "DATE(scmlog.date) as date, SUM(commits_lines.added) as added, SUM(commits_lines.removed) as removed", :joins => :commit, :order => "DATE(scmlog.date)", :group => "DATE(scmlog.date)")


    # Add Column Headers
    data_table = GoogleVisualr::DataTable.new
    data_table.new_column('string', 'Date' )
    data_table.new_column('number', 'Added')
    data_table.new_column('number', 'Removed')

    rows = []
    @commits_lines.each do |commit_line|
      rows.push([commit_line.date.strftime("%Y-%m-%d"), commit_line.added, commit_line.removed])
    end

    # Add Rows and Values
    data_table.add_rows(rows)
    @chart = Chart.area_chart('Lines Added/Remove in time', 1024, 600, data_table)
  end

  def change_dates
    repository = params[:repository]
    set_dates(repository)
    render :partial => "date_selectors", :locals => {:from => @from, :to => @to}, :layout => false
  end

  def change_dates_for_metrics_evo
    set_dates(params[:repository])
    @from += 1.month
    render :partial => "date_selectors_month", :locals => {:from => @from, :to => @to}
  end

private
  def set_defaults
    @repositories = Repository.all.collect{|repository| [repository.name, repository.id]}
    set_dates(@repositories.first[1])
  end

  def set_dates(repository)
    @from = Commit.first(:conditions => "repository_id = #{repository}", :order => "date ASC").date
    @to = Commit.first(:conditions => "repository_id = #{repository}", :order => "date DESC").date
  end

  #def set_dates_for_metrics_evo(branches)
  #  @from = MetricsEvo.first(:conditions => "branch_id in (#{branches.collect{|name,id| id}.join(',')})", :order => "date ASC").date
  #  @to = MetricsEvo.first(:conditions => "branch_id in (#{branches.collect{|name,id| id}.join(',')})", :order => "date DESC").date
  #end
end
