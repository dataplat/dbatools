function Get-DbaFeature {
    <#
    .SYNOPSIS
        Runs the SQL Server feature discovery report (setup.exe /Action=RunDiscovery)

    .DESCRIPTION
        Runs the SQL Server feature discovery report (setup.exe /Action=RunDiscovery)

        Inspired by Dave Mason's (@BeginTry) post at
        https://itsalljustelectrons.blogspot.be/2018/04/SQL-Server-Discovery-Report.html

        Assumptions:
        1. The sub-folder "Microsoft SQL Server" exists in [System.Environment]::GetFolderPath("ProgramFiles"),
        even if SQL was installed to a non-default path. This has been
        verified on SQL 2008R2 and SQL 2012. Further verification may be needed.
        2. The discovery report displays installed components for the version of SQL
        Server associated with setup.exe, along with installed components of all
        lesser versions of SQL Server that are installed.

    .PARAMETER ComputerName
        The target computer. If the target is not localhost, it must have PowerShell remoting enabled.

        Note that this is not the SqlInstance, but rather the ComputerName

    .PARAMETER Credential
        Allows you to login to servers using alternative credentials. To use:

        $cred = Get-Credential, then pass $cred object to the -Credential parameter.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Feature, Component
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaFeature

    .EXAMPLE
        PS C:\> Get-DbaFeature -ComputerName sql2017, sql2016, sql2005

        Gets all SQL Server features for all instances on sql2017, sql2016 and sql2005.

    .EXAMPLE
        PS C:\> Get-DbaFeature -Verbose

        Gets all SQL Server features for all instances on localhost. Outputs to screen if no instances are found.

    .EXAMPLE
        PS C:\> Get-DbaFeature -ComputerName sql2017 -Credential ad\sqldba

        Gets all SQL Server features for all instances on sql2017 using the ad\sqladmin credential (which has access to the Windows Server).

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    begin {
        $scriptblock = {
            $setup = Get-ChildItem -Recurse -Include setup.exe -Path "$([System.Environment]::GetFolderPath("ProgramFiles"))\Microsoft SQL Server" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'Setup Bootstrap\\SQL' -or $_.FullName -match 'Bootstrap\\Release\\Setup.exe' -or $_.FullName -match 'Bootstrap\\Setup.exe' } |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($setup) {
                $null = Start-Process -FilePath $setup.FullName -ArgumentList "/Action=RunDiscovery /q" -Wait
                $parent = Split-Path (Split-Path $setup.Fullname)
                $xmlfile = Get-ChildItem -Recurse -Include SqlDiscoveryReport.xml -Path $parent | Sort-Object LastWriteTime -Descending | Select-Object -First 1

                if ($xmlfile) {
                    Get-Content -Path $xmlfile
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $text = Invoke-Command2 -ComputerName $Computer -ScriptBlock $scriptblock -Credential $Credential -Raw

                if (-not $text) {
                    Write-Message -Level Verbose -Message "No features found on $computer"
                }

                $xml = [xml]($text)
                foreach ($result in $xml.ArrayOfDiscoveryInformation.DiscoveryInformation) {
                    [pscustomobject]@{
                        ComputerName = $computer
                        Product      = $result.Product
                        Instance     = $result.Instance
                        InstanceID   = $result.InstanceID
                        Feature      = $result.Feature
                        Language     = $result.Language
                        Edition      = $result.Edition
                        Version      = $result.Version
                        Clustered    = $result.Clustered
                        Configured   = $result.Configured
                    }
                }
            } catch {
                Stop-Function -Continue -ErrorRecord $_ -Message "Failure"
            }
        }
    }
}