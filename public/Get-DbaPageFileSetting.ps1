
function Get-DbaPageFileSetting {
    <#
    .SYNOPSIS
        Retrieves Windows page file configuration from SQL Server host computers for performance analysis.

    .DESCRIPTION
        This command uses CIM to retrieve detailed Windows page file configuration from SQL Server host computers. Page file settings directly impact SQL Server performance during memory pressure scenarios, making this essential for capacity planning and troubleshooting performance issues.
        
        The function returns comprehensive details including current usage, peak usage, initial and maximum sizes, and whether page files are automatically managed by Windows. This information helps DBAs identify potential memory bottlenecks and validate that page file configurations align with SQL Server best practices.

        Note that this may require local administrator privileges for the relevant computers.

    .PARAMETER ComputerName
        The target SQL Server instance or instances.
        This can be the name of a computer, a SMO object, an IP address, an AD Computer object, a connection string or a SQL Instance.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Management, OS, PageFile
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaPageFileSetting

    .EXAMPLE
        PS C:\> Get-DbaPageFileSetting -ComputerName ServerA,ServerB

        Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA and ServerB

    .EXAMPLE
        PS C:\> 'ServerA' | Get-DbaPageFileSetting

        Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName) {
            $splatDbaCmObject = @{
                ComputerName    = $computer
                EnableException = $true
            }
            if ($Credential) { $splatDbaCmObject["Credential"] = $Credential }

            try {
                $compSys = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_computersystem"
                if (-not $CompSys.automaticmanagedpagefile) {
                    $pagefiles = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefile"
                    $pagefileUsages = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefileUsage"
                    $pagefileSettings = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefileSetting"
                }
            } catch {
                Stop-Function -Message "Failed to retrieve information from $($computer.ComputerName)" -ErrorRecord $_ -Target $computer -Continue
            }

            if (-not $CompSys.automaticmanagedpagefile) {
                foreach ($file in $pagefiles) {
                    $settings = $pagefileSettings | Where-Object Name -EQ $file.Name
                    $usage = $pagefileUsages | Where-Object Name -EQ $file.Name

                    # pagefile is not automatic managed, so return settings
                    New-Object Dataplat.Dbatools.Computer.PageFileSetting -Property @{
                        ComputerName      = $computer.ComputerName
                        AutoPageFile      = $CompSys.automaticmanagedpagefile
                        FileName          = $file.name
                        Status            = $file.status
                        SystemManaged     = ($settings.InitialSize -eq 0) -and ($settings.MaximumSize -eq 0)
                        LastModified      = $file.LastModified
                        LastAccessed      = $file.LastAccessed
                        AllocatedBaseSize = $usage.AllocatedBaseSize # in MB, between Initial and Maximum Size
                        InitialSize       = $settings.InitialSize # in MB
                        MaximumSize       = $settings.MaximumSize # in MB
                        PeakUsage         = $usage.peakusage # in MB
                        CurrentUsage      = $usage.currentusage # in MB
                    }
                }
            } else {
                # pagefile is automatic managed, so there are no settings
                New-Object Dataplat.Dbatools.Computer.PageFileSetting -Property @{
                    ComputerName      = $computer
                    AutoPageFile      = $CompSys.automaticmanagedpagefile
                    FileName          = $null
                    Status            = $null
                    SystemManaged     = $null
                    LastModified      = $null
                    LastAccessed      = $null
                    AllocatedBaseSize = $null
                    InitialSize       = $null
                    MaximumSize       = $null
                    PeakUsage         = $null
                    CurrentUsage      = $null
                }
            }
        }
    }
}