function Get-DbaXESessionTemplate {
    <#
    .SYNOPSIS
        Retrieves metadata from Extended Event session templates to help you discover and select pre-built monitoring solutions.

    .DESCRIPTION
        Retrieves metadata from Extended Event session templates stored in XML format, showing you what pre-built Extended Event sessions are available before importing them to your SQL Server instances. This saves you from manually browsing template files or guessing what monitoring solutions exist for specific scenarios.

        Use this command when you need to set up Extended Event monitoring but want to start with proven templates rather than building sessions from scratch. It's particularly helpful for discovering templates that monitor specific areas like performance, deadlocks, or security events.

        The function parses templates and returns key information including the template name, category, source, SQL Server compatibility, and description. You can filter results by pattern matching or select specific templates by name.

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
        Specifies the directory path containing Extended Event template XML files. Defaults to the built-in dbatools template repository.
        Use this when you want to browse custom or additional templates stored in your own directory instead of the default collection.

    .PARAMETER Pattern
        Filters templates by searching for the specified text pattern across template names, categories, sources, and descriptions.
        Use this to quickly find templates related to specific monitoring scenarios like "deadlock", "performance", or "security" without browsing all available templates.

    .PARAMETER Template
        Specifies the exact name(s) of specific templates to retrieve, matching the template file names without the .xml extension.
        Use this when you know the specific template names you want to examine, such as "Deadlock_Tracking" or "Query_Duration_Performance".

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
        [string[]]$Path = "$script:PSModuleRoot\bin\XEtemplates",
        [string]$Pattern,
        [string[]]$Template,
        [switch]$EnableException
    )
    begin {
        $xmlpath = Join-DbaPath $script:PSModuleRoot "bin" "xetemplates-metadata.xml"
        $metadata = Import-Clixml $xmlpath
        # In case people really want a "like" search, which is slower
        $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*")
    }
    process {
        foreach ($directory in $Path) {
            $files = Get-ChildItem "$(Join-DbaPath $directory *.xml)"

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
                            [PSCustomObject]@{
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
                        [PSCustomObject]@{
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