function Get-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Parses Extended Event XML templates. Defaults to parsing templates in the dbatools template repository (\bin\xetemplates\).

    .DESCRIPTION
        Parses Extended Event XML templates. Defaults to parsing templates in the dbatools template repository (\bin\xetemplates\).

        The default repository contains templates from:
        Microsoft's Templates that come with SSMS
        Jes Borland's "Everyday Extended Events" presentation and GitHub repository (https://github.com/grrlgeek/extended-events)
        Christian Grafe (@ChrGraefe) XE Repo: https://github.com/chrgraefe/sqlscripts/blob/master/XE-Events/
        Erin Stellato's Blog: https://www.sqlskills.com/blogs/erin/

        Some profile templates converted using:
        sp_SQLskills_ConvertTraceToExtendedEvents.sql
        Jonathan M. Kehayias, SQLskills.com
        http://sqlskills.com/blogs/jonathan

    .PARAMETER Path
        The path to the template directory. Defaults to the dbatools template repository (\bin\xetemplates\).

    .PARAMETER Pattern
        Specify a pattern for filtering. Alternatively, you can use Out-GridView -Passthru to select objects and pipe them to Import-DbaXESessionTemplate

    .PARAMETER Template
        Specifies one or more of the templates provided by dbatools. Press tab to cycle through the list of options.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaXESessionTemplate

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate

        Returns information about all the templates in the local dbatools repository.

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate | Out-GridView -PassThru | Import-DbaXESessionTemplate -SqlInstance sql2017 | Start-DbaXESession

        Allows you to select a Session template, then import it to the specified instance and start the session.

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate -Path "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates"

        Returns information about all the templates in your local XEventTemplates repository.

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate -Pattern duration

        Returns information about all the templates that match the word "duration" in the title, category or body.

    .EXAMPLE
        PS C:\> Get-DbaXESessionTemplate | Select-Object *

        Returns more information about the template, including the full path/filename.

    #>

    [CmdletBinding()]
    param (
        [string[]]$Path = "$script:PSModuleRoot\bin\xetemplates",
        [string]$Pattern,
        [string[]]$Template,
        [switch]$EnableException
    )
    begin {
        $metadata = Import-Clixml "$script:PSModuleRoot\bin\xetemplates-metadata.xml"
        # In case people really want a "like" search, which is slower
        $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*")
    }
    process {
        foreach ($directory in $Path) {
            $files = Get-ChildItem "$directory\*.xml"

            if ($Template) {
                $files = $files | Where-Object BaseName -in $Template
            }

            foreach ($file in $files) {
                try {
                    $xml = [xml](Get-Content $file)
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue
                }

                foreach ($session in $xml.event_sessions) {
                    $meta = $metadata | Where-Object Name -eq $session.event_session.name
                    if ($Pattern) {
                        if (
                            # There's probably a better way to do this
                            ($session.event_session.name -match $Pattern) -or
                            ($session.event_session.TemplateCategory.'#text' -match $Pattern) -or
                            ($session.event_session.TemplateSource -match $Pattern) -or
                            ($session.event_session.TemplateDescription.'#text' -match $Pattern) -or
                            ($session.event_session.TemplateName.'#text' -match $Pattern) -or
                            ($meta.Source -match $Pattern)
                        ) {
                            [pscustomobject]@{
                                Name          = $session.event_session.name
                                Category      = $session.event_session.TemplateCategory.'#text'
                                Source        = $meta.Source
                                Compatibility = ("$($meta.Compatibility)").ToString().Replace(",", "")
                                Description   = $session.event_session.TemplateDescription.'#text'
                                TemplateName  = $session.event_session.TemplateName.'#text'
                                Path          = $file
                                File          = $file.Name
                            } | Select-DefaultView -ExcludeProperty File, TemplateName, Path
                        }
                    } else {
                        [pscustomobject]@{
                            Name          = $session.event_session.name
                            Category      = $session.event_session.TemplateCategory.'#text'
                            Source        = $meta.Source
                            Compatibility = $meta.Compatibility.ToString().Replace(",", "")
                            Description   = $session.event_session.TemplateDescription.'#text'
                            TemplateName  = $session.event_session.TemplateName.'#text'
                            Path          = $file
                            File          = $file.Name
                        } | Select-DefaultView -ExcludeProperty File, TemplateName, Path
                    }
                }
            }
        }
    }
}