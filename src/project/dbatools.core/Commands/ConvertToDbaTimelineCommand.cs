#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Net;
using System.Text;
using Dataplat.Dbatools.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates interactive HTML timeline visualizations from SQL Server job history, backup history, and database growth event data
/// </summary>
[Cmdlet(VerbsData.ConvertTo, "DbaTimeline")]
public sealed class ConvertToDbaTimelineCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server data to convert into a timeline (Get-DbaAgentJobHistory, Get-DbaDbBackupHistory, or Find-DbaDbGrowthEvent output).</summary>
    [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true)]
    public object[] InputObject { get; set; } = null!;

    /// <summary>Removes the row labels showing SQL instance and item names from the left side of the timeline chart.</summary>
    [Parameter]
    public SwitchParameter ExcludeRowLabel { get; set; }

    /// <summary>The Google Charts date pattern used for tooltip dates and the timeline axis.</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidatePattern("\\A[dMyE,./ -]+\\z")]
    public string DateFormat { get; set; } = "dd/MM";

    private List<List<TimelineRow>> _body = null!;
    private List<string> _separators = null!;
    private List<object?> _servers = null!;
    private string? _callerName;

    protected override void BeginProcessing()
    {
        // PS: $body = $servers = @()
        _body = new List<List<TimelineRow>>();
        _separators = new List<string>();
        _servers = new List<object?>();
        _callerName = null;
    }

    protected override void ProcessRecord()
    {
        // PS has no interrupt guard in process — Test-FunctionInterrupt runs only in end{},
        // so every pipeline block still registers servers, sniffs, and can warn again.
        if (InputObject is null || InputObject.Length == 0)
        {
            return;
        }

        object? first = InputObject[0];

        List<TimelineRow> rows;
        object? firstBase = first is PSObject firstWrapped ? firstWrapped.BaseObject : first;

        if (PsEqTruthy(DotAccess(first, "TypeName"), "AgentJobHistory"))
        {
            _callerName = "Get-DbaAgentJobHistory";
            rows = MapRows(MapAgentJobHistory);
        }
        else if (firstBase is BackupHistory)
        {
            // PS: the caller name is assigned WITH a leading space in the source.
            _callerName = " Get-DbaDbBackupHistory";
            rows = MapRows(MapBackupHistory);
        }
        else if (PsProperty.Has(first, "EventClass") && PsProperty.Has(first, "ChangeInSize"))
        {
            _callerName = "Find-DbaDbGrowthEvent";
            rows = MapRows(MapGrowthEvent);
        }
        else
        {
            // sorry to be so formal, can't help it ;)
            StopFunction("Unsupported input data. To request support for additional commands, please file an issue at dbatools.io/issues and we'll take a look");
            return;
        }

        // PS: $body += "$($data | ForEach-Object { "['..'],," })" — the outer expandable string
        // joins the per-row strings with the SESSION $OFS (default single space, read per
        // call like PS resolves it); ONE body string per block.
        _body.Add(rows);
        _separators.Add(GetOfsSeparator());
    }

    protected override void EndProcessing()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
        {
            return;
        }

        // PS: $body is an @() object array (its elements are strings) — the emitted middle
        // object must be object[], not string[].
        object[] bodyStrings = new object[_body.Count];
        for (int i = 0; i < _body.Count; i++)
        {
            List<string> rowStrings = new List<string>();
            foreach (TimelineRow row in _body[i])
            {
                string label = _servers.Count == 1
                    ? row.VLabel
                    : string.Format(CultureInfo.InvariantCulture, "[{0}] {1}", row.Instance, row.VLabel);
                rowStrings.Add(string.Format(CultureInfo.InvariantCulture,
                    "['{0}','{1}','{2}',{3}, {4}],",
                    EncodeJavaScript(label), EncodeJavaScript(row.HLabel), EncodeJavaScript(row.Style),
                    row.StartDate, row.EndDate));
            }
            bodyStrings[i] = string.Join(_separators[i], rowStrings);
        }

        // PS: $servers -join ', ' — elements stringify through the language conversion
        // (invariant numerics, bag rendering), same as expandable-string interpolation.
        List<string> serverParts = new List<string>();
        foreach (object? server in _servers)
        {
            serverParts.Add(WebUtility.HtmlEncode(PsText(server)));
        }

        // The raw-string constant ends at "showRowLabels:" (a trailing space would be too
        // fragile to keep in source), so the separating space is concatenated explicitly.
        string tooltipDateFormat = DateFormat.IndexOf("y", StringComparison.OrdinalIgnoreCase) >= 0 ? DateFormat : DateFormat + "/yy";
        string footer = FooterA.Replace("dd/MM/yy HH:mm:ss", tooltipDateFormat + " HH:mm:ss")
            + " "
            + (ExcludeRowLabel.ToBool() ? "false" : "true")
            + FooterB.Replace("dd/MM HH:mm", DateFormat + " HH:mm")
            + _callerName
            + FooterC
            + string.Join(", ", serverParts)
            + FooterD;

        // PS: $begin, $body, $end — the pipeline flattens exactly one level, so the body array
        // itself is the middle output object (String[] with one element per process block).
        WriteObject(HeaderLiteral);
        WriteObject(bodyStrings, false);
        WriteObject(footer);
    }

    private sealed class TimelineRow
    {
        public string Instance = "";
        public string VLabel = "";
        public string HLabel = "";
        public string Style = "";
        public string StartDate = "";
        public string EndDate = "";
    }

    private List<TimelineRow> MapRows(Func<object?, TimelineRow> mapper)
    {
        // PS: $data = $InputObject | Select-Object @{...} — every element of the block's array
        // is mapped with the branch chosen from element [0]. The pipeline SKIPS null elements,
        // so Select-Object never sees them and no row is produced for a null.
        List<TimelineRow> rows = new List<TimelineRow>();
        foreach (object? element in InputObject)
        {
            if (element is null)
            {
                continue;
            }
            object? instance = DotAccess(element, "SqlInstance");
            if (!ListContainsPs(_servers, instance))
            {
                object? instanceBase = instance is PSObject wrapped ? wrapped.BaseObject : instance;
                if (instanceBase is not string && LanguagePrimitives.GetEnumerable(instanceBase) is IEnumerable instances)
                {
                    foreach (object? entry in instances)
                    {
                        _servers.Add(entry);
                    }
                }
                else
                {
                    _servers.Add(instance);
                }
            }
            rows.Add(mapper(element));
        }
        return rows;
    }

    /// <summary>
    /// PS dot-access on a property: a real (adapted/ETS) property wins; otherwise an
    /// enumerable base gets MEMBER-ACCESS ENUMERATION (per-element property values collected
    /// into object[], null when nothing matched). DBNull values flow through unwashed —
    /// [int]DBNull must fail like the PS cast does.
    /// </summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
        {
            return null;
        }
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is not null)
        {
            object? value;
            try
            {
                value = direct.Value;
            }
            catch
            {
                return null;
            }
            if (value is PSObject valueWrapped && valueWrapped.BaseObject is not PSCustomObject)
            {
                return valueWrapped.BaseObject;
            }
            return value;
        }
        object? baseValue = wrapped.BaseObject;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            List<object?> collected = new List<object?>();
            foreach (object? element in elements)
            {
                if (element is null)
                {
                    continue;
                }
                PSPropertyInfo? elementProperty = PSObject.AsPSObject(element).Properties[name];
                if (elementProperty is not null)
                {
                    try
                    {
                        collected.Add(elementProperty.Value);
                    }
                    catch
                    {
                        collected.Add(null);
                    }
                }
            }
            if (collected.Count == 0)
            {
                return null;
            }
            return collected.ToArray();
        }
        return null;
    }

    private TimelineRow MapAgentJobHistory(object? element)
    {
        TimelineRow row = new TimelineRow();
        row.Instance = PsText(DotAccess(element, "SqlInstance"));
        _ = DotAccess(element, "InstanceName");
        row.VLabel = PsText(DotAccess(element, "Job"));
        row.HLabel = PsText(DotAccess(element, "Status"));
        row.Style = ConvertTimelineStatusColor(DotAccess(element, "Status"));
        row.StartDate = ConvertToJsDate(DotAccess(element, "StartDate"));
        row.EndDate = ConvertToJsDate(DotAccess(element, "EndDate"));
        return row;
    }

    private TimelineRow MapBackupHistory(object? element)
    {
        TimelineRow row = new TimelineRow();
        row.Instance = PsText(DotAccess(element, "SqlInstance"));
        _ = DotAccess(element, "InstanceName");
        row.VLabel = PsText(DotAccess(element, "Database"));
        row.HLabel = PsText(DotAccess(element, "Type"));
        row.Style = "";
        row.StartDate = ConvertToJsDate(DotAccess(element, "Start"));
        row.EndDate = ConvertToJsDate(DotAccess(element, "End"));
        return row;
    }

    private TimelineRow MapGrowthEvent(object? element)
    {
        TimelineRow row = new TimelineRow();
        row.Instance = PsText(DotAccess(element, "SqlInstance"));
        _ = DotAccess(element, "InstanceName");
        row.VLabel = PsText(DotAccess(element, "DatabaseName"));

        // PS: switch ([int]$_.EventClass) { 92..95 } default "Unknown"; a failing [int] cast
        // (non-numeric, DBNull) is statement-terminating in the calculated property and leaves
        // the value empty. The hLabel and Style expressions each read and convert EventClass
        // INDEPENDENTLY (a volatile getter can legitimately give them different values).
        int hLabelClass;
        bool hLabelClassKnown;
        try
        {
            hLabelClass = (int)LanguagePrimitives.ConvertTo(DotAccess(element, "EventClass"), typeof(int), CultureInfo.InvariantCulture);
            hLabelClassKnown = true;
        }
        catch
        {
            hLabelClass = 0;
            hLabelClassKnown = false;
        }
        if (hLabelClassKnown)
        {
            switch (hLabelClass)
            {
                case 92: row.HLabel = "Data Grow"; break;
                case 93: row.HLabel = "Log Grow"; break;
                case 94: row.HLabel = "Data Shrink"; break;
                case 95: row.HLabel = "Log Shrink"; break;
                default: row.HLabel = "Unknown"; break;
            }
        }
        else
        {
            row.HLabel = "";
        }

        // PS: if ([int]$_.EventClass -in 92, 93) { "#36B300" } else { "#FF8C00" } — own read.
        int styleClass;
        bool styleClassKnown;
        try
        {
            styleClass = (int)LanguagePrimitives.ConvertTo(DotAccess(element, "EventClass"), typeof(int), CultureInfo.InvariantCulture);
            styleClassKnown = true;
        }
        catch
        {
            styleClass = 0;
            styleClassKnown = false;
        }
        row.Style = styleClassKnown && (styleClass == 92 || styleClass == 93) ? "#36B300" : "#FF8C00";
        row.StartDate = ConvertToJsDate(DotAccess(element, "StartTime"));
        row.EndDate = ConvertToJsDate(DotAccess(element, "EndTime"));
        return row;
    }

    /// <summary>The session $OFS as PS expandable-string joins resolve it (default one space).</summary>
    private string GetOfsSeparator()
    {
        object? ofsValue;
        try
        {
            ofsValue = SessionState.PSVariable.GetValue("OFS");
        }
        catch
        {
            ofsValue = null;
        }
        if (ofsValue is null)
        {
            return " ";
        }
        return (string)LanguagePrimitives.ConvertTo(ofsValue, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>Encode data for a single-quoted JavaScript literal inside an HTML script element.</summary>
    private static string EncodeJavaScript(string value)
    {
        StringBuilder result = new StringBuilder();
        foreach (char character in value)
        {
            switch (character)
            {
                case '\\': result.Append("\\\\"); break;
                case '\'': result.Append("\\'"); break;
                case '<': result.Append("\\u003c"); break;
                case '>': result.Append("\\u003e"); break;
                case '&': result.Append("\\u0026"); break;
                default:
                    if (character < 32 || character == '\u2028' || character == '\u2029')
                    {
                        result.Append("\\u");
                        result.Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        result.Append(character);
                    }
                    break;
            }
        }
        return result.ToString();
    }

    /// <summary>
    /// PS: if ($value -eq "literal") — the -eq operator FILTERS an enumerable left operand
    /// (result = matching elements) and the if applies PS truthiness, so @("X") -eq "X" is
    /// truthy while a scalar compares directly (the W5-027 PsEqTruthy pattern).
    /// </summary>
    private static bool PsEqTruthy(object? left, object? right)
    {
        object? baseLeft = left is PSObject wrapped ? wrapped.BaseObject : left;
        if (baseLeft is not string && LanguagePrimitives.GetEnumerable(baseLeft) is IEnumerable elements)
        {
            foreach (object? element in elements)
            {
                if (PsOps.Eq(element, right))
                {
                    return true;
                }
            }
            return false;
        }
        return PsOps.Eq(left, right);
    }

    /// <summary>
    /// PS expandable-string rendering of a property value: LanguagePrimitives string
    /// conversion (numerics render invariant — 1.5 stays "1.5" under fr-FR), property bags
    /// render "@{...}", enumerables join their converted elements with the session $OFS, and
    /// null becomes empty.
    /// </summary>
    private string PsText(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        object? baseValue = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (baseValue is not string && LanguagePrimitives.GetEnumerable(baseValue) is IEnumerable elements)
        {
            List<string> parts = new List<string>();
            foreach (object? element in elements)
            {
                parts.Add(PsText(element));
            }
            return string.Join(GetOfsSeparator(), parts);
        }
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// Private helper Convert-DbaTimelineStatusColor absorbed: SQL Agent status literal to html
    /// color, PS switch case-insensitivity preserved, default "#FF00CC". The helper's MANDATORY
    /// [string]$Status rejects a null/empty binding — the calculated property errors (statement
    /// class) and the Style field renders EMPTY, not magenta.
    /// Internal (not private) so the TB-013 offline tests can pin the switch directly;
    /// SCALAR inputs (and the array early-return) never touch SessionState, so a bare
    /// instance suffices for those pins ONLY. Non-array collections route through PsText →
    /// GetOfsSeparator, which reads the session $OFS and silently defaults to a space when
    /// SessionState is unavailable — so a bare instance cannot validate the join; the
    /// collection pins drive the REAL cmdlet end-to-end in a runspace instead (codex
    /// TB-013 r3/r4).
    /// </summary>
    internal string ConvertTimelineStatusColor(object? status)
    {
        if (status is null)
        {
            return string.Empty;
        }
        // PS parameter binding REJECTS an ARRAY for a scalar [string] parameter (lab-proven
        // both editions, even single-element arrays) — the helper call errors and Style is
        // empty. NON-array collections (ArrayList, List<string>) DO bind, converting with the
        // $OFS join (also lab-proven), which PsText below reproduces.
        object? statusBase = status is PSObject statusWrapped ? statusWrapped.BaseObject : status;
        if (statusBase is Array)
        {
            return string.Empty;
        }
        string text = PsText(status);
        if (text.Length == 0)
        {
            return string.Empty;
        }
        if (PsString.Eq(text, "Failed")) { return "#FF3D3D"; }
        if (PsString.Eq(text, "Succeeded")) { return "#36B300"; }
        if (PsString.Eq(text, "Retry")) { return "#FFFF00"; }
        if (PsString.Eq(text, "Canceled")) { return "#C2C2C2"; }
        if (PsString.Eq(text, "In Progress")) { return "#00CCFF"; }
        return "#FF00CC";
    }

    /// <summary>
    /// JavaScript Date consumes Gregorian components regardless of the host calendar.
    /// Preserve invariant input conversion, zero-based month and padded date/time fields.
    /// Invalid input retains the source helper's empty calculated-property value.
    /// </summary>
    internal static string ConvertToJsDate(object? inputDate)
    {
        try
        {
            DateTime date = (DateTime)LanguagePrimitives.ConvertTo(inputDate, typeof(DateTime), CultureInfo.InvariantCulture);
            CultureInfo culture = CultureInfo.InvariantCulture;
            int month = int.Parse(date.ToString("MM", culture), NumberStyles.Integer, CultureInfo.InvariantCulture) - 1;
            return string.Format(CultureInfo.InvariantCulture,
                "new Date({0}, {1}, {2}, {3}, {4}, {5})",
                date.ToString("yyyy", culture),
                month.ToString(CultureInfo.InvariantCulture),
                date.ToString("dd", culture),
                date.ToString("HH", culture),
                date.ToString("mm", culture),
                date.ToString("ss", culture));
        }
        catch
        {
            return string.Empty;
        }
    }

    /// <summary>PS: $value -notin $servers (case-insensitive -eq semantics per element).</summary>
    private static bool ListContainsPs(List<object?> list, object? value)
    {
        foreach (object? entry in list)
        {
            if (PsOps.Eq(entry, value))
            {
                return true;
            }
        }
        return false;
    }

    private static string NormalizeCrlf(string text)
    {
        // The PS here-string literals carry the checked-out file's CRLF line endings; the .cs
        // source may be checked out either way, so canonicalize.
        return text.Replace("\r\n", "\n").Replace("\n", "\r\n");
    }

    private static readonly string HeaderLiteral = NormalizeCrlf(@"<html>
<head>
<!-- Developed by Marcin Gminski, marcin.gminski.net, 2018 -->
<!-- Load jQuery required to autosize timeline -->
<script src=""https://code.jquery.com/jquery-3.3.1.min.js"" integrity=""sha256-FgpCb/KJQlLNfOu91ta32o/NMZxltwRo8QtmkMRdAu8="" crossorigin=""anonymous""></script>
<!-- Load Bootstrap -->
<script src=""https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"" integrity=""sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa"" crossorigin=""anonymous""></script>
<link rel=""stylesheet"" href=""https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css"" integrity=""sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u"" crossorigin=""anonymous"">
<link rel=""stylesheet"" href=""https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap-theme.min.css"" integrity=""sha384-rHyoN1iRsVXV4nD0JutlnGaslCJuC7uwjduW9SVrLvRYooPp2bWYgmgJQIXwl/Sp"" crossorigin=""anonymous"">
<!-- Load Google Charts library -->
<script type=""text/javascript"" src=""https://www.gstatic.com/charts/loader.js""></script>
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
    <script type=""text/javascript"">
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

        dataTable.addRows([");

    private static readonly string FooterA = NormalizeCrlf(@"]);
        var paddingHeight = 20;
        var rowHeight = dataTable.getNumberOfRows() * 41;
        var chartHeight = rowHeight + paddingHeight;
        dataTable.insertColumn(2, {type: 'string', role: 'tooltip', p: {html: true}});
        var dateFormat = new google.visualization.DateFormat({
          pattern: 'dd/MM/yy HH:mm:ss'
        });
        function encodeHtml(value) {
          return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/\x22/g, '&quot;').replace(/'/g, '&#39;');
        }
        for (var i = 0; i < dataTable.getNumberOfRows(); i++) {
          var duration = (dataTable.getValue(i, 5).getTime() - dataTable.getValue(i, 4).getTime()) / 1000;
          var hours = parseInt( duration / 3600 ) % 24;
          var minutes = parseInt( duration / 60 ) % 60;
          var seconds = duration % 60;
          var tooltip = '<div class=""timeline-tooltip""><span>' +
            encodeHtml(dataTable.getValue(i, 1)).split("","").join(""<br />"")  + '</span></div><div class=""timeline-tooltip""><span>' +
            encodeHtml(dataTable.getValue(i, 0)) + '</span>: ' +
            dateFormat.formatValue(dataTable.getValue(i, 4)) + ' - ' +
            dateFormat.formatValue(dataTable.getValue(i, 5)) + '</div>' +
            '<div class=""timeline-tooltip""><span>Duration: </span>' +
            hours + 'h ' + minutes + 'm ' + seconds + 's ';
          dataTable.setValue(i, 2, tooltip);
        }
        var options = {
            timeline: {
                rowLabelStyle: { },
                barLabelStyle: { },
                showRowLabels:");

    private static readonly string FooterB = NormalizeCrlf(@"
            },
            hAxis: {
                format: 'dd/MM HH:mm',
            },
        }
        // Autosize chart. It would not be enough to just count rows and expand based on row height as there can be overlapping rows.
        // this will draw the chart, get the size of the underlying div and apply that size to the parent container and redraw:
        chart.draw(dataTable, options);
        // get the size of the chold div:
        var realheight= parseInt($(""#Chart div:first-child div:first-child div:first-child div svg"").attr( ""height""))+70;
        // set the height:
        options.height=realheight
        // draw again:
        chart.draw(dataTable, options);
    }
</script>
</head>
<body>
    <div class=""container-fluid"">
    <div class=""pull-left""><h3><code>");

    private static readonly string FooterC = NormalizeCrlf(@"</code> timeline for <code>");

    private static readonly string FooterD = NormalizeCrlf(@"</code></h3></div><div class=""pull-right text-right""><img class=""text-right"" style=""vertical-align:bottom; margin-top: 10px;"" src=""https://dbatools.io/thor.png"" width=150></div>
         <div class=""clearfix""></div>
         <div class=""col-12"">
            <div class=""chart"" id=""Chart""></div>
         </div>
         <hr>
    <p><a href=""https://dbatools.io"">dbatools.io</a> - the community's sql powershell module. Find us on Twitter: <a href=""https://twitter.com/psdbatools"">@psdbatools</a> | Chart by <a href=""https://twitter.com/marcingminski"">@marcingminski</a></p>
</div>
</body>
</html>");
}
