function  ConvertTo-DbaTimeline {
    <#
        .SYNOPSIS
            Converts InputObject to a html timeline using Google Chart

        .DESCRIPTION
            This function accepts input as pipeline from the following psdbatools functions:
                Get-DbaAgentJobHistory
                Get-DbaBackupHistory
                (more to come...)
            And generates Bootstrap based, HTML file with Google Chart Timeline

        .PARAMETER InputObject

            Pipe input, must an output from the above functions.

        .NOTES
            Tags: Internal
            Author: Marcin Gminski (@marcingminski)

            Dependency: ConvertTo-JsDate, Convert-DbaTimelineStatusColor
            Requirements: None

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
-           License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/ConvertTo-DbaTimeline

        .EXAMPLE
            Get-DbaAgentJobHistory -SqlInstance sql-1 -StartDate ‘2018-08-13 00:00’ -EndDate ‘2018-08-13 23:59’ -NoJobSteps | ConvertTo-DbaTimeline | Out-File C:\temp\DbaAgentJobHistory.html -Encoding ASCII
            Get-DbaBackupHistory -SqlInstance sql-1 -Since ‘2018-08-13 00:00’ | ConvertTo-DbaTimeline | Out-File C:\temp\DbaBackupHistory.html -Encoding ASCII

    #>

    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object[]]$InputObject
    )
    begin {
        #need to capture calling process to know what we are being asked for i.e. JobHistory, BackupHistory etc?
        #I dont know of any way apart from Get-PSCallStack but that return the whole stack but in order to the last
        #function should be the one that called this one? Not sure if this is correct but it works.
        $caller = Get-PSCallStack | Select -Property * | Select -last 1
        #build html container
@"
<html>
<head>
<!-- Developed by Marcin Gminski, https://marcin.gminski.net, 2018 -->
<!-- Load jQuery required to autosize timeline -->
<script src="https://code.jquery.com/jquery-3.3.1.min.js" integrity="sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8=" crossorigin="anonymous"></script>
<!-- Load Bootstrap -->
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap-theme.min.css" integrity="sha384-rHyoN1iRsVXV4nD0JutlnGaslCJuC7uwjduW9SVrLvRYooPp2bWYgmgJQIXwl/Sp" crossorigin="anonymous">
<!-- Load Google Charts library -->
<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
<!-- a bit of custom styling to work with bootstrap grid -->
<style>

    html,body{height:100%;background-color:#c2c2c2;}
    .viewport {height:100%}

    .chart{
        background-color:#fff;
        text-align:left;
        padding:0;
        border:1px solid #7D7D7D;
        -webkit-box-shadow:1px 1px 3px 0 rgba(0,0,0,.45);
        -moz-box-shadow:1px 1px 3px 0 rgba(0,0,0,.45);
        box-shadow:1px 1px 3px 0 rgba(0,0,0,.45)
    }
    .badge-custom{background-color:#939}
    .container {
        height:100%;
    }
    .fill{
        width:100%;
        height:100%;
        min-height:100%;
        padding:10px;
    }
    .timeline-tooltip{
        border:1px solid #E0E0E0;
        font-family:Arial,Helvetica;
        font-size:10pt;
        padding:12px
    }
    .timeline-tooltip div{padding:6px}
    .timeline-tooltip span{font-weight:700}
</style>
    <script type="text/javascript">
    google.charts.load('43', {'packages':['timeline']});
    google.charts.setOnLoadCallback(drawChart);
    function drawChart() {
        var container = document.getElementById('Chart');
        var chart = new google.visualization.Timeline(container);
        var dataTable = new google.visualization.DataTable();
        dataTable.addColumn({type: 'string', id: 'vLabel'});
        dataTable.addColumn({type: 'string', id: 'hLabel'});
        dataTable.addColumn({type: 'string', role: 'style' });
        dataTable.addColumn({type: 'date', id: 'date_start'});
        dataTable.addColumn({type: 'date', id: 'date_end'});

        dataTable.addRows([
"@
    }

    process
    {
        $BaseObject = $InputObject.PsObject.BaseObject
        #This is where do column mapping:
        if ($caller.Position -Like "*Get-DbaAgentJobHistory*") {
            $CallerName = "Get-DbaAgentJobHistory"
            $data = $input | Select @{ Name="SqlInstance"; Expression = {$_.SqlInstance}}, @{ Name="InstanceName"; Expression = {$_.InstanceName}}, @{ Name="vLabel"; Expression = {$_.Job} }, @{ Name="hLabel"; Expression = {$_.Status} }, @{ Name="Style"; Expression = {$(Convert-DbaTimelineStatusColor($_.Status))} }, @{ Name="StartDate"; Expression = {$(ConvertTo-JsDate($_.StartDate))} }, @{ Name="EndDate"; Expression = {$(ConvertTo-JsDate($_.EndDate))} }

        }

        if ($caller.Position -Like "*Get-DbaBackupHistory*") {
            $CallerName = "Get-DbaBackupHistory"
            $data = $input | Select @{ Name="SqlInstance"; Expression = {$_.SqlInstance}}, @{ Name="InstanceName"; Expression = {$_.InstanceName}}, @{ Name="vLabel"; Expression = {$_.Database} }, @{ Name="hLabel"; Expression = {$_.Type} }, @{ Name="StartDate"; Expression = {$(ConvertTo-JsDate($_.Start))} }, @{ Name="EndDate"; Expression = {$(ConvertTo-JsDate($_.End))} }
        }
                "$( $data | %{"['$($_.vLabel)','$($_.hLabel)','$($_.Style)',$($_.StartDate), $($_.EndDate)],"})"
        }
    end {
@"
]);
        var paddingHeight = 20;
        var rowHeight = dataTable.getNumberOfRows() * 41;
        var chartHeight = rowHeight + paddingHeight;
        dataTable.insertColumn(2, {type: 'string', role: 'tooltip', p: {html: true}});
        var dateFormat = new google.visualization.DateFormat({
          pattern: 'dd/MM/yy HH:mm:ss'
        });
        for (var i = 0; i < dataTable.getNumberOfRows(); i++) {
          var duration = (dataTable.getValue(i, 5).getTime() - dataTable.getValue(i, 4).getTime()) / 1000;
          var hours = parseInt( duration / 3600 ) % 24;
          var minutes = parseInt( duration / 60 ) % 60;
          var seconds = duration % 60;
          var tooltip = '<div class="timeline-tooltip"><span>' +
            dataTable.getValue(i, 1).split(",").join("<br />")  + '</span></div><div class="timeline-tooltip"><span>' +
            dataTable.getValue(i, 0) + '</span>: ' +
            dateFormat.formatValue(dataTable.getValue(i, 4)) + ' - ' +
            dateFormat.formatValue(dataTable.getValue(i, 5)) + '</div>' +
            '<div class="timeline-tooltip"><span>Duration: </span>' +
            hours + 'h ' + minutes + 'm ' + seconds + 's ';
          dataTable.setValue(i, 2, tooltip);
        }
        var options = {
            timeline: {
                rowLabelStyle: { },
                barLabelStyle: { },
            },
            hAxis: {
                format: 'dd/MM HH:mm',
            },
        }
        // Autosize chart. It would not be enough to just count rows and expand based on row height as there can be overlappig rows.
        // this will draw the chart, get the size of the underlying div and apply that size to the parent container and redraw:
        chart.draw(dataTable, options);
        // get the size of the chold div:
        var realheight= parseInt(`$("#Chart div:first-child div:first-child div:first-child div svg").attr( "height"))+70;
        // set the height:
        options.height=realheight
        // draw again:
        chart.draw(dataTable, options);
    }
</script>
</head>
<body>
    <div class="container-fluid">
    <div class="pull-left"><h3><code>$($CallerName)</code> timeline for server <code>$($BaseObject.SqlInstance)</code></h3></div><div class="pull-right text-right"><img class="text-right" style="vertical-align:bottom; margin-top: 10px;" src="https://dbatools.io/wp-content/uploads/2016/05/dbatools-logo-1.png" width=150></div>
         <div class="clearfix"></div>
         <div class="col-12">
            <div class="chart" id="Chart"></div>
         </div>
         <hr>
    <p><a href="https://dbatools.io">dbatools.io</a> - the community's sql powershell module. Find us on Twitter: <a href="https://twitter.com/psdbatools">@psdbatools</a> | Chart by <a href="https://twitter.com/marcingminski">@marcingminski</a></p>
</div>
</body>
</html>
"@
    }
}
