function Invoke-DbaDiagnosticQueryScriptParser {
    [CmdletBinding(DefaultParameterSetName = "Default")]

    Param(
        [parameter(Mandatory = $true)]
        [ValidateScript( {Test-Path $_})]
        [System.IO.FileInfo]$filename,
        [Switch]$NoQueryTextColumn,
        [Switch]$NoPlanColumn,
        [Switch]$NoColumnParsing
    )

    $out = "Parsing file {0}" -f $filename
    write-verbose -Message $out

    $ParsedScript = @()
    [string]$scriptpart = ""

    $fullscript = Get-Content -Path $filename

    $start = $false
    $querynr = 0
    $DBSpecific = $false

    if ($NoQueryTextColumn) {$QueryTextColumn = ""}  else {$QueryTextColumn = ", t.[text] AS [Complete Query Text]"}
    if ($NoPlanColumn) {$PlanTextColumn = ""} else {$PlanTextColumn = ", qp.query_plan AS [Query Plan]"}

    foreach ($line in $fullscript) {
        if ($start -eq $false) {
            if ($line -match "You have the correct major version of SQL Server for this diagnostic information script") {
                $start = $true
            }
            continue
        }

        if ($line.StartsWith("-- Database specific queries ***") -or ($line.StartsWith("-- Switch to user database **"))) {
            $DBSpecific = $true
        }

        if (!$NoColumnParsing) {
            if (($line -match "-- uncomment out these columns if not copying results to Excel") -or ($line -match "-- comment out this column if copying results to Excel")) {
                $line = $QueryTextColumn + $PlanTextColumn
            }
        }

        if ($line -match "-{2,}\s{1,}(.*) \(Query (\d*)\) \((\D*)\)") {
            $prev_querydescription = $Matches[1]
            $prev_querynr = $Matches[2]
            $prev_queryname = $Matches[3]

            if ($querynr -gt 0) {
                $properties = @{QueryNr = $querynr; QueryName = $queryname; DBSpecific = $DBSpecific; Description = $queryDescription; Text = $scriptpart}
                $newscript = New-Object -TypeName PSObject -Property $properties
                $ParsedScript += $newscript
                $scriptpart = ""
            }

            $querydescription = $prev_querydescription
            $querynr = $prev_querynr
            $queryname = $prev_queryname
        }
        else {
            if (!$line.startswith("--") -and ($line.trim() -ne "") -and ($null -ne $line) -and ($line -ne "\n")) {
                $scriptpart += $line + "`n"
            }
        }
    }

    $properties = @{QueryNr = $querynr; QueryName = $queryname; DBSpecific = $DBSpecific; Description = $queryDescription; Text = $scriptpart}
    $newscript = New-Object -TypeName PSObject -Property $properties
    $ParsedScript += $newscript
    $ParsedScript
}
