function Get-DbaPageFileSetting {
<#
    .SYNOPSIS
        Returns information about the network connection of the target computer including NetBIOS name, IP Address, domain name and fully qualified domain name (FQDN).
    
    .DESCRIPTION
        WMI class Win32_ComputerSystem tells us if Page File is managed automatically.
        If TRUE all other properties do not exist.
        If FALSE classes Win32_PageFile, Win32_PageFileSetting en Win32_PageFileUsage are examined.
        CIM is used, first via WinRM, and if not successful, via DCOM.
        This function needs to be executed as a user with local admin rights on the target computer(s).
    
    .PARAMETER ComputerName
        The Server that you're connecting to.
        This can be the name of a computer, a SMO object, an IP address or a SQL Instance.
    
    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    
    .EXAMPLE
        Get-DbaPageFileSetting -ComputerName ServerA,ServerB
        
        Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA and ServerB
    
    .EXAMPLE
        'ServerA' | Get-DbaPageFileSetting
        
        Returns a custom object displaying ComputerName, AutoPageFile, FileName, Status, LastModified, LastAccessed, AllocatedBaseSize, InitialSize, MaximumSize, PeakUsage, CurrentUsage  for ServerA
    
    .NOTES
        Tags: CIM
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )
        
        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    
    .LINK
        https://dbatools.io/Get-DbaPageFileSetting
#>
    
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("cn", "host", "ServerInstance", "Server", "SqlServer")]
        [DbaInstance]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($Computer in $ComputerName) {
            Write-Message -Level VeryVerbose -Message "Connecting to $($Computer.ComputerName)" -Target $Computer
            $splatDbaCmObject = @{
                ComputerName   = $computer
                EnableException = $true
            }
            if ($Credential) { $splatDbaCmObject["Credential"] = $Credential }
            
            try {
                $compSys = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_computersystem"
                if (-not $CompSys.automaticmanagedpagefile) {
                    $PF = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefile" # deprecated !
                    $PFU = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefileUsage"
                    $PFS = Get-DbaCmObject @splatDbaCmObject -Query "SELECT * FROM win32_pagefileSetting"
                }
            }
            catch {
                Stop-Function -Message "Failed to retrieve information from $($Computer.ComputerName)" -ErrorRecord $_ -Target $Computer -Continue
            }
            
            if (-not $CompSys.automaticmanagedpagefile) {
                # pagefile is not automatic managed, so return settings
                New-Object Sqlcollaborative.Dbatools.Computer.PageFileSetting -Property @{
                    ComputerName         = $Computer.ComputerName
                    AutoPageFile         = $CompSys.automaticmanagedpagefile
                    FileName             = $PF.name # deprecated !
                    Status               = $PF.status # deprecated !
                    LastModified         = $PF.LastModified
                    LastAccessed         = $PF.LastAccessed
                    AllocatedBaseSize    = $PFU.AllocatedBaseSize # in MB, between Initial and Maximum Size
                    InitialSize          = $PFS.InitialSize # in MB
                    MaximumSize          = $PFS.MaximumSize # in MB
                    PeakUsage            = $PFU.peakusage # in MB
                    CurrentUsage         = $PFU.currentusage # in MB
                }
            }
            else {
                # pagefile is automatic managed, so there are no settings
                New-Object Sqlcollaborative.Dbatools.Computer.PageFileSetting -Property @{
                    ComputerName         = $Computer
                    AutoPageFile         = $CompSys.automaticmanagedpagefile
                    FileName             = $null
                    Status               = $null
                    LastModified         = $null
                    LastAccessed         = $null
                    AllocatedBaseSize    = $null
                    InitialSize          = $null
                    MaximumSize          = $null
                    PeakUsage            = $null
                    CurrentUsage         = $null
                }
            }
        }
    }
}
