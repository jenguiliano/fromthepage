class ExportController < ApplicationController
  require 'zip'

  def index
    @collection = Collection.find_by(id: params[:collection_id])
  end

  def show
    render :layout => false
  end

  def tei
    params[:format] = 'xml'# if params[:format].blank?

    @context = ExportContext.new

    @user_contributions =
      User.find_by_sql("SELECT  user_id user_id,
                                users.print_name print_name,
                                count(*) edit_count,
                                min(page_versions.created_on) first_edit,
                                max(page_versions.created_on) last_edit
                        FROM    page_versions
                        INNER JOIN pages
                            ON page_versions.page_id = pages.id
                        INNER JOIN users
                            ON page_versions.user_id = users.id
                        WHERE pages.work_id = #{@work.id}
                          AND page_versions.transcription IS NOT NULL
                        GROUP BY user_id
                        ORDER BY count(*) DESC")

    @work_versions = PageVersion.joins(:page).where(['pages.work_id = ?', @work.id]).order("work_version DESC").all

    @all_articles = @work.articles
    @person_articles = []
    @place_articles = []
    @other_articles = []

    @all_articles.each do |article|
      # TODO replace this with legitimate flow control once I get to a ruby lang doc
      other = true
      if article.categories.where(:title => 'Places').count > 0
        @place_articles << article
        other = false
      end
      if article.categories.where(:title => 'People').count > 0
        @person_articles << article
        other = false
      end
      @other_articles << article if other
    end

    #@work = Work.includes(:pages => [:notes, :ia_leaf => :ia_work]).find(@work.id)

    render :layout => false, :content_type => "application/xml", :template => "export/tei.html.erb"
  end

  def subject_csv
    cookies['download_finished'] = 'true'
    send_data(@collection.export_subjects_as_csv,
              :filename => "fromthepage_subjects_export_#{@collection.id}_#{Time.now.utc.iso8601}.csv",
              :type => "application/csv")
  end
  
  def table_csv
    cookies['download_finished'] = 'true'
    send_data(export_tables_as_csv(@work),
              :filename => "fromthepage_tables_export_#{@collection.id}_#{Time.now.utc.iso8601}.csv",
              :type => "application/csv")
    
  end

  def export_all_works
    cookies['download_finished'] = 'true'
    @collection = Collection.find_by(id: params[:collection_id])
    @works = Work.where(collection_id: @collection.id)

#create a zip file which is automatically downloaded to the user's machine
    respond_to do |format|
      format.html
      format.zip do
      compressed_filestream = Zip::OutputStream.write_buffer do |zos|
        @works.each do |work|
          @work = work
          export_view = render_to_string(:action => 'show', :formats => [:html], :work_id => work.id, :layout => false, :encoding => 'utf-8')
          zos.put_next_entry "#{work.title}.xhtml"
          zos.print export_view
        end
      end
      compressed_filestream.rewind
      send_data compressed_filestream.read, filename: "#{@collection.title}.zip"
      end
    end

  end

private

  def export_tables_as_csv(work)
    raw_headings = work.table_cells.pluck('DISTINCT header')
    headings = []
    raw_headings.each do |raw_heading|
      munged_heading = raw_heading  #.sub(/^\s*!?/,'').sub(/\s*$/,'')
      headings << "#{munged_heading} (text)"
      headings << "#{munged_heading} (subject)"
    end
    
    csv_string = CSV.generate(:force_quotes => true) do |csv|
      csv << (['Page Title', 'Page Position', 'Page URL', 'Section (text)', 'Section (subjects)', 'Section (subject categories)' ] + headings)
      work.pages.includes(:table_cells).each do |page|
        unless page.table_cells.empty?
          page_url=url_for({:controller=>'display',:action => 'display_page', :page_id => page.id, :only_path => false})
          page_cells = [page.title, page.position, page_url]
          data_cells = Array.new(headings.count + 1, "")
          section_title_text = nil
          section_title_subjects = nil
          section_title_categories = nil
          section = nil
          row = nil
          page.table_cells.includes(:section).each do |cell|
            if section != cell.section
              section_title_text = XmlSourceProcessor::cell_to_plaintext(cell.section.title)
              section_title_subjects = XmlSourceProcessor::cell_to_subject(cell.section.title)
              section_title_categories = XmlSourceProcessor::cell_to_category(cell.section.title)
            end 
            if row != cell.row
              if row
                # write the record to the CSV and start a new record
                csv << (page_cells + data_cells)
              end
              data_cells = Array.new(headings.count + 3, "")            
              data_cells[0] = section_title_text
              data_cells[1] = section_title_subjects
              data_cells[2] = section_title_categories
              row = cell.row
            end
            
            target = raw_headings.index(cell.header) + 1
            data_cells[target*2-1] = XmlSourceProcessor.cell_to_plaintext(cell.content)
            data_cells[target*2] = XmlSourceProcessor.cell_to_subject(cell.content)
          end
        end
      end
    end
    csv_string
  end


end