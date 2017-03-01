function Get-DbaDiagnosticQueryScript
{
<#
.SYNOPSIS 
Get-DbaDiagnosticQueryScript downloads the most recent version of all Glenn Berry DMV scripts

.DESCRIPTION
The dbatools module will have the diagnostice queries pre-installed. Use this only to update to a more recent version or specific versions.
This function is mainly used by Invoke-DbaDiagnosticQuery, but can also be used independently to download the Glenn Berry DMV scripts.
Use this function to pre-download the scripts from a device with an Internet connection.
The function Invoke-DbaDiagnosticQuery will try to download these scripts automatically, but it obviously needs an internet connection to do that.
	
.EXAMPLE   
Get-DbaDiagnosticQueryScript -ScriptLocation c:\users\myusername\documents\

Downloads the most recent version of all Glenn Berry DMV scripts to the specified location.
If ScriptLocation is not specified, the "My Documents" location will be used

#>

[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
Param(
    [ValidateScript({Test-Path $_})]
    [System.IO.FileInfo]$ScriptLocation = [Environment]::GetFolderPath("mydocuments")
)
    [Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null

    Write-Output "Downloading SQL Server Diagnostic Query scripts"

    $GlennBerryRSS = "http://www.sqlskills.com/blogs/glenn/feed/"
    $GlennBerrySQL = @()

    $rss = Invoke-WebRequest -uri $GlennBerryRSS -UseBasicParsing

    foreach($link in $rss.Links.outerHTML)
    {
        if ($link -Match "https:\/\/dl.dropboxusercontent*(.+)\/SQL(.+)\.sql")
        {
            $URL = $matches[0]

            if ([System.Web.HttpUtility]::UrlDecode($URL) -Match "SQL Server (.+) Diagnostic")
            {
                $SQLVersion = $matches[1].Replace(" ", "")
            }

            if ([System.Web.HttpUtility]::UrlDecode($URL) -Match "\((.+) (.+)\)")
            {
                $FileYear = "{0}" -f $matches[2]
                [int]$MonthNr = [CultureInfo]::InvariantCulture.DateTimeFormat.MonthNames.IndexOf($matches[1]) +1
                $FileMonth = "{0:00}" -f $MonthNr
            }

            $GlennBerrySQL += New-Object -TypeName PSObject -Property @{URL=$URL; SQLVersion=$SQLVersion; FileYear=$FileYear; FileMonth=$FileMonth; FileVersion=0}
        }
    }

    foreach($group in $GlennBerrySQL | Group-Object FileYear)
    {
        $maxmonth = "{0:00}" -f ($group.Group.FileMonth | Measure-Object -Maximum).Maximum
        foreach($item in $GlennBerrySQL | Where-Object FileYear -eq $group.Name)
        {
            if ($item.FileMonth -eq "00")
            {
                $item.FileMonth = $maxmonth
            }
        }
    }

    foreach($item in $GlennBerrySQL)
    {
        $item.FileVersion = "$($item.FileYear)$($item.FileMonth)"
    }


    foreach($item in $GlennBerrySQL | Sort-Object FileVersion -Descending | Where-Object FileVersion -eq ($GlennBerrySQL.FileVersion | Measure-Object -Maximum).Maximum)
    {
        $filename = "{0}\SQLServerDiagnosticQueries_{1}_{2}.sql" -f $ScriptLocation, $item.SQLVersion, $item.FileVersion
        Invoke-WebRequest -Uri $item.URL -OutFile $filename
    }
}
