function Invoke-DbaAgentJobHistoryGantt {
<#
.SYNOPSIS
Produces a Gantt chart (timeline) based on SQL Agent job history.

.DESCRIPTION
Reads job history for a given SQL instance, date & time range, 
then outputs that history to a temp HTML file that can be rendered
as a Gantt chart (timeline) using Google charts.
The .html file opens using your default browser.

This is handly for visualizing:
1. Which jobs ran in the timeframe
2. How long jobs ran for
3. The job outcome (success / failure)
4. Available gaps between jobs
5. Overlapping jobs

.PARAMETER SqlInstance
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
    SqlCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Job
    The name of the job from which the history is wanted. If unspecified, all jobs will be processed.

.PARAMETER StartDate
    The DateTime starting from which the history is wanted. If unspecified, all available records will be processed.

.PARAMETER EndDate
    The DateTime before which the history is wanted. If unspecified, all available records will be processed

.PARAMETER NoJobSteps
    Use this switch to discard all job steps, and return only the job outcome.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
    Tags: Job, Agent, History
    Author: Paul Bell, freewheel101@gmail.com
    Editor: VSCode

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

.LINK
    https://dbatools.io/Invoke-DbaJobGantt

    Google timeline chart template
    https://developers.google.com/chart/interactive/docs/gallery/timeline
   
    Customisation for color mapping
    http://stackoverflow.com/questions/23268616/color-in-googles-timeline-chart-bars-based-in-the-a-specific-value
   
    Timeline chart data format
    https://developers.google.com/chart/interactive/docs/gallery/timeline#data-format

.EXAMPLE
    Invoke-DbaAgentJobHistoryGantt -SqlInstance sql2\Inst2K17 -StartDate '2018/03/20 18:00:00' -EndDate '2018/03/21 06:00:00' -NoJobSteps

    Returns the SQL Agent Job execution history results between 2018/03/20 18:00:00 and 2018/03/21 06:00:00 on sql2\Inst2K17.

#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Server")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Job,
        [DateTime]$StartDate =  ([DateTime]::Today.AddDays(-1).AddHours(18)),
        [DateTime]$EndDate = ([DateTime]::Today.AddHours(6)),
        [switch]$NoJobSteps,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
       [string]$GoogleChartTemplate = @'
<html>
  <head>
    <script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
        
    <script type="text/javascript">
      google.charts.load("current", {packages:["timeline"]});
      google.charts.setOnLoadCallback(drawChart);
        
      function drawChart() {
        var container = document.getElementById('SQLTimelineDIV');
        var chart = new google.visualization.Timeline(container);
        var dataTable = new google.visualization.DataTable();
        dataTable.addColumn({ type: 'string', id: 'Job' });
        dataTable.addColumn({ type: 'string', id: 'dummy bar label' });
        dataTable.addColumn({ type: 'string', role: 'tooltip', 'p': {'html': true}});
        dataTable.addColumn({ type: 'date', id: 'Start' });
        dataTable.addColumn({ type: 'date', id: 'End' });
        // <DATATABLEADDROWS>
        
        var arrcolors = [];
        var colorMap = {
            // should contain a map of RunStatus -> color for every RunStatus
            Failed: 'red',
            Succeeded: '#0E6655',
            Retry: '#FFC300',
            Canceled: 'black'
        }
        //  
        var tooltip = '';
        var runStatus = '';
        for (var i = 0; i < dataTable.getNumberOfRows(); i++) {
          tooltip = dataTable.getValue(i, 2)

          switch (true) {
              case (tooltip.indexOf('Status:&nbsp;<B>Failed') >= 0):
                  runStatus = 'Failed';
                  break;
              case (tooltip.indexOf('Status:&nbsp;<B>Retry') >= 0):
                  runStatus = 'Retry';
                  break;
              case (tooltip.indexOf('Status:&nbsp;<B>Canceled') >= 0):
                  runStatus = 'Canceled';
                  break;
              default:
                  runStatus = 'Succeeded';
          }

          arrcolors.push(colorMap[runStatus]);
        };
            
        var options = {
                      colors: arrcolors,
                        timeline: {
                            colorByRowLabel: false,
                            showBarLabels: false,
                            groupByRowLabel: true,
                            rowLabelStyle: { fontSize: 9 }, 
                            barLabelStyle: { fontSize: 7 }
                            },
                        avoidOverlappingGridLines: true,
                        tooltip: {isHtml: true}
        };
        if (dataTable.getNumberOfRows() > 0) {
          chart.draw(dataTable, options);
        } else {
          document.getElementById('SQLTimelineDIV').innerHTML = '<B>No data found.</B>'
        }
      }

      function toolTipHTML(jobName, stepname, startDate, endDate, duration, runStatus, RetriesAttempted) {
          var retHtml = '<div style="padding:5px 5px 5px 5px;font-family: Arial, Helvetica, sans-serif;background-color: #ffffb3;">' +
                        'Job:&nbsp;<B>' + jobName + '</B><BR>' +
                        'Step:&nbsp;<B>' + stepname + '</B><BR>' +
                        'Start:&nbsp;' + startDate + '<BR>' +
                        'End:&nbsp;' + endDate + '<BR>' +
                        'Retries attempted:&nbsp;' + RetriesAttempted + '<BR>' +
                        'Duration:&nbsp;' + duration + '<BR>' +
                        'Status:&nbsp;<B>' + runStatus + '</B>'
                        '</div>';
          return retHtml;
      }
  </script>
</head>
  <body>        
    <H3 style="font-family: Arial, Helvetica, sans-serif; font-weight: lighter;">
    Server: <SERVER><p>
    <DATERANGE>
    </H3>
    <div id="SQLTimelineDIV" style="height: 90%;"></div>
  </body>
</html>
'@

      [string]$rowlabel = ''
      [string]$Tooltip = ''
      [string]$RunStatus = ''
      [DateTime]$RunEndDateTime = (get-date)
      [int]$rowcount = 0
      [string]$TempFile = ''
      [string]$InstanceFileName =''
      [string]$TempHTMLFile = ''
      [string]$tablerows = ''
      [string]$htmContent = ''
      [string]$DataStartDate = ''
      [String]$DataEndDate = ''
      [string]$ToolJobStart = ''
      [string]$ToolJobEnd = ''
      [string]$outspan = ''
      
      $RunStates = @('Failed','Succeeded','Retry','Canceled')

    } # begin

    process {

    # Format date data for the chart
    function formatChartDate {
        param ([datetime]$DataDate)

        [string]$DateFormat = 'MM/dd/yyyy HH:mm:ss'
                
        $YYYY   = $DataDate.tostring($DateFormat).Substring(6,4)
        $MM     = $DataDate.tostring($DateFormat).Substring(0,2)
        $DD     = $DataDate.tostring($DateFormat).Substring(3,2)
        $HH     = $DataDate.tostring($DateFormat).Substring(11,2)
        $NN     = $DataDate.tostring($DateFormat).Substring(14,2)
        $SS     = $DataDate.tostring($DateFormat).Substring(17,2)
        [string]$chartDate = 'new Date({0},{1},{2},{3},{4},{5})' -f $YYYY, $MM, $DD, $HH, $NN, $SS
        return $chartDate
    }

    # Format date for the tooltip - locale format
    function tooltipDate {
        param ([datetime]$toolDate)
        [string]$returnDate = $toolDate.tostring((Get-culture).DateTimeFormat.ShortDatePattern + ' ' + (Get-culture).DateTimeFormat.ShortTimePattern)
        return $returnDate
    }

    # Produce a verbose timespan
    function verboseTS {
        param ([timespan]$ts)
        [string]$verboseSpan =  '{0} seconds' -f $ts.Seconds.tostring()
        
        if ($ts.Minutes -gt 0) {
            $verboseSpan = $ts.minutes.tostring() + ' minutes, ' + $verboseSpan
        }

        if ($ts.Hours -gt 0) {
            $verboseSpan = $ts.Hours.tostring() + ' hours, ' + $verboseSpan
        }

        if ($ts.Days -gt 0) {
            $verboseSpan = $ts.Days.tostring() + ' days, ' + $verboseSpan
        }
        return $verboseSpan
    }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Connecting to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $JobHistory = Get-DbaAgentJobHistory -SqlInstance $server -SqlCredential $SqlCredential -Job $Job -StartDate $StartDate -EndDate $EndDate -NoJobSteps:$NoJobSteps -EnableException:$EnableException

            $SortedJobHistory = $JobHistory | select-object JobID, JobName, StepID, StepName, RunDate, RunStatus, RunDuration, RetriesAttempted | Sort-Object JobID, StepID, RunDate

            $InstanceFileName = $instance.tostring().replace('\','_').replace('.','_')

            # Get a temp html file name for output
            $TempFile = [IO.Path]::GetTempFileName() | Rename-Item -NewName { $_ -replace 'tmp$', 'html' } -PassThru
            
            $TempDIR = [System.io.path]::GetDirectoryName($TempFile)
            $TempName = [System.io.path]::GetFileName($TempFile)

            $TempHTMLFile = join-path -Path $TempDIR -ChildPath "$InstanceFileName.$TempName"

            $rowcount = 0
            $tablerows = ''
            $htmContent = $GoogleChartTemplate

            # Generate the HTML to be rendered
            foreach ($JobRun in $SortedJobHistory) {
                $rowcount += 1

                # The RunDuration needs interpretation.
                # e.g. a value of '829' indicates 8 minutes and 29 seconds or 0000:08:29
                [string]$Runtime = ($JobRun.RunDuration).tostring("0000:00:00")

                $Runhours = $Runtime.substring(0,4)
                $Runmins = $Runtime.substring(5,2)
                $Runsecs = $Runtime.substring(8,2)
                $ts = New-TimeSpan -Hours $Runhours -Minutes $Runmins -Seconds $Runsecs

                $RunEndDateTime = ($JobRun.RunDate) + $ts
                $RunStatus = $RunStates[$JobRun.RunStatus]

                $DataStartDate = formatChartDate -DataDate $JobRun.RunDate
                $DataEndDate = formatChartDate -DataDate $RunEndDateTime
                
                $ToolJobStart = tooltipDate -toolDate $JobRun.RunDate
                $ToolJobEnd = tooltipDate -toolDate $RunEndDateTime

                $ts = New-TimeSpan -Start $JobRun.RunDate -End $RunEndDateTime

                $outspan = verboseTS -ts $ts
                
                if ($NoJobSteps) {
                  $rowlabel  = $JobRun.JobName
                } else {
                  $rowlabel  = "{0} ({1})" -f $JobRun.JobName, $JobRun.StepName
                }

                $tooltip = 'toolTipHTML(''{0}'',''{1}'',''{2}'',''{3}'',''{4}'',''{5}'',{6})' -f  $JobRun.JobName, $JobRun.StepName, $ToolJobStart, $ToolJobEnd, $outspan, $RunStatus, $JobRun.RetriesAttempted
                $tablerows += '[''{0}'', ''{1}'', {2}, {3}, {4}],{5}' -f $rowlabel,  $rowcount, $tooltip, $DataStartDate, $DataEndDate, [environment]::newline

             } # foreach (job run)

            # Do we have any data rows to add?
            if ($rowcount -gt 0) {
              [string]$AddRows = '
                      dataTable.addRows([
                  <TABLEROWS>
                      ]);
              '
              $htmContent = $htmContent.replace('// <DATATABLEADDROWS>',$AddRows)
              $htmContent = $htmContent.replace('<TABLEROWS>',$tablerows)
            }

            [string]$CharDateFrom = $StartDate.tostring((Get-culture).DateTimeFormat.ShortDatePattern + ' ' + (Get-culture).DateTimeFormat.ShortTimePattern)
            [string]$CharDateTo = $EndDate.tostring((Get-culture).DateTimeFormat.ShortDatePattern + ' ' + (Get-culture).DateTimeFormat.ShortTimePattern)

            [string]$DisplayServer = $server.tostring().replace('[','').replace(']','')
            $daterange = '{0}&nbsp;&nbsp;to&nbsp;&nbsp;{1}' -f $CharDateFrom, $CharDateTo
            $htmContent = $htmContent.replace('<SERVER>',$DisplayServer)
            $htmContent = $htmContent.replace('<DATERANGE>',$daterange)

            # Write the file
            add-content -Path $TempHTMLFile -Value $htmContent -Encoding Ascii           
            
            # Launch the file
            invoke-item -Path $TempHTMLFile
    } # foreach (instance)
  } # process 
} #function
