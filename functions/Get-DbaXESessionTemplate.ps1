function Get-DbaXESessionTemplate {
 <#
    .SYNOPSIS
    Parses Extended Event XML templates. Defaults to parsing templates in our template repository (\bin\xetemplates\)

    .DESCRIPTION
    Parses Extended Event XML templates. Defaults to parsing templates in our template repository (\bin\xetemplates\)
    
    The default repository contains templates from:
    
            Microsoft's Templates that come with SSMS
            Jes Borland's "Everyday Extended Events" presentation and GitHub repository (https://github.com/grrlgeek/extended-events)
            Christian Gräfe's XE Repo: https://github.com/chrgraefe/sqlscripts/blob/master/XE-Events/
    
    Some profile templates converted using:
    
            sp_SQLskills_ConvertTraceToExtendedEvents.sql
            Jonathan M. Kehayias, SQLskills.com
            http://sqlskills.com/blogs/jonathan

    .PARAMETER Path
    The path to the template directory. Defaults to our template repository (\bin\xetemplates\)

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Get-DbaXESessionTemplate

    .EXAMPLE
    Get-DbaXESessionTemplate

    Returns information about all the templates in the local dbatools repository

    .EXAMPLE
    Get-DbaXESessionTemplate | Out-GridView -PassThru | Import-DbaXESessionTemplate -SqlInstance sql2017 | Start-DbaXESession

    Allows you to select a Session template then import to an instance named

    .EXAMPLE
    Get-DbaXESessionTemplate -Path "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates"

    Returns information about all the templates in your local XEventTemplates repository

#>
    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\xetemplates",
        [switch]$EnableException
    )
    process {
        foreach ($directory in $Path) {
            $files = Get-ChildItem "$directory\*.xml"
            foreach ($file in $files) {
                try {
                    $xml = [xml](Get-Content $file)
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }
                
                foreach ($session in $xml.event_sessions) {
                    [pscustomobject]@{
                        Name      = $session.event_session.name
                        Category   = $session.event_session.TemplateCategory.'#text'
                        Description = $session.event_session.TemplateDescription.'#text'
                        TemplateName = $session.event_session.TemplateName.'#text'
                        Path       = $file
                        File       = $file.Name
                    } | Select-DefaultView -ExcludeProperty File, TemplateName, Path
                }
            }
        }
    }
}