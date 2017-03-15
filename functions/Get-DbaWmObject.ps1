function Get-DbaWmObject
{
    <#
        .SYNOPSIS
            Retrieves Wmi-Style information from computers.
        
        .DESCRIPTION
            This function centralizes all requests for information retrieved from Get-WmiObject or Get-CimInstance.
            It uses different protocols as available in this order:
            - Cim over WinRM
            - Cim over DCOM
            - Wmi
            - Wmi over PowerShell Remoting
            It remembers channels that didn't work and will henceforth avoid them. It remembers invalid credentials and will avoid reusing them.
            Much of its behavior can be configured using Test-DbaWmConnection.
        
        .PARAMETER ClassName
            The name of the class to retrieve.
        
        .PARAMETER ComputerName
            The computer(s) to connect to. Defaults to localhost.
        
        .PARAMETER Credential
            Credentials to use. Invalid credentials will be stored in a credentials cache and not be reused.
        
        .PARAMETER Namespace
            The namespace of the class to use.
        
        .PARAMETER DoNotUse
            Connection Protocols that should not be used.
        
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
        
        .EXAMPLE
            PS C:\> Get-DbaWmObject win32_OperatingSystem
        
            Retrieves the common operating system informations from the local computer.
        
        .EXAMPLE
            PS C:\> Get-DbaWmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM
        
            Retrieves the common operating system informations from the server sql2014.
            It will use the credewntials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Class')]
        [string]
        $ClassName,
        
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $ComputerName = $env:COMPUTERNAME,
        
        [System.Management.Automation.PSCredential]
        $Credential,
        
        [string]
        $Namespace,
        
        [sqlcollective.dbatools.Connection.ManagementConnectionType[]]
        $DoNotUse = "None",
        
        [switch]
        $Silent
    )
    
    Begin
    {
        #region Configuration Values
        $disable_cache = Get-DbaConfigValue -Name "Cache.Management.Disable.All" -Fallback $false
        $disable_badcredentialcache = Get-DbaConfigValue -Name "Cache.Management.Disable.BadCredentialList" -Fallback $false
        #endregion Configuration Values
        
        if ($false) { $Connection = New-Object sqlcollective.dbatools.Connection.ManagementConnection }
    }
    Process
    {
        :main foreach ($Computer in $ComputerName)
        {
            # Since all connection caching runs using lower-case strings, making it lowercase here simplifies things.
            $Computer = $Computer.ToLower()
            
            Write-Message -Message "[$Computer] Retrieving Management Information" -Level VeryVerbose
            
            #region Settle connection object
            if ($disable_cache)
            {
                $Connection = New-Object sqlcollective.dbatools.Connection.ManagementConnection
                $Connection.ComputerName = $Computer
            }
            else
            {
                if ($Connection = [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer])
                {
                    
                }
                else
                {
                    $Connection = New-Object sqlcollective.dbatools.Connection.ManagementConnection
                    $Connection.ComputerName = $Computer
                    
                    [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection
                }
            }
            #endregion Settle connection object
            
            # Ensure using the right credentials
            $cred = $Connection.GetCredential($Credential, $disable_badcredentialcache, $PSBoundParameters.ContainsKey("Credential"))
            
            # 
            $Excluded = @()
            foreach ($item in $DoNotUse) { $Excluded += $item }
            
            :sub while ($true)
            {
                try { $conType = $Connection.GetConnectionType(($Excluded -join ",")) }
                catch
                {
                    if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                    Stop-Function -Message "[$Computer] Could not find a valid connection protocol, interrupting execution now" -Target $Computer -Category OpenError -Continue -ContinueLabel "main"
                }
                
                switch ($conType.ToString())
                {
                    #region CimRM
                    "CimRM"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over WinRM"
                        try
                        {
                            $Session = New-CimSession -ComputerName $Computer -Credential $cred -ErrorAction Stop
                            $parameters = @{
                                CimSession = $Session
                                ClassName = $ClassName
                                ErrorAction = 'Stop'
                            }
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $parameters["Namespace"] = $Namespace }
                            Get-CimInstance @parameters
                            
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over WinRM - Success!"
                            $Connection.ReportSuccess('CimRM')
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                            if ($Session) { Remove-CimSession -CimSession $Session }
                            continue main
                        }
                        catch
                        {
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over WinRM - Failed!"
                            if ($Session) { Remove-CimSession -CimSession $Session }
                            
                            if ($_.CategoryInfo.Category -eq "AuthenticationError")
                            {
                                if (-not $disable_badcredentialcache) { $Connection.AddBadCredential($cred) }
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                                Stop-Function -Message "[$Computer] Invalid connection credentials" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            elseif ($_.CategoryInfo.Category -eq "ObjectNotFound")
                            {
                                Stop-Function -Message "[$Computer] Invalid class name, not found in current namespace" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            else
                            {
                                $Connection.ReportFailure('CimRM')
                                $Excluded += "CimRM"
                                continue sub
                            }
                        }
                    }
                    #endregion CimRM
                    
                    #region CimDCOM
                    "CimDCOM"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over DCOM"
                        try
                        {
                            $sessionoption = New-CimSessionOption -Protocol DCOM
                            $Session = New-CimSession -ComputerName $Computer -Credential $cred -ErrorAction Stop -SessionOption $sessionoption
                            $parameters = @{
                                CimSession = $Session
                                ClassName = $ClassName
                                ErrorAction = 'Stop'
                            }
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $parameters["Namespace"] = $Namespace }
                            Get-CimInstance @parameters
                            
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over DCOM - Success!"
                            $Connection.ReportSuccess('CimDCOM')
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                            if ($Session) { Remove-CimSession -CimSession $Session }
                            continue main
                        }
                        catch
                        {
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using Cim over DCOM - Failed!"
                            if ($Session) { Remove-CimSession -CimSession $Session }
                            
                            if ($_.CategoryInfo.Category -eq "AuthenticationError")
                            {
                                if (-not $disable_badcredentialcache) { $Connection.AddBadCredential($cred) }
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                                Stop-Function -Message "[$Computer] Invalid connection credentials" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            elseif ($_.CategoryInfo.Category -eq "ObjectNotFound")
                            {
                                Stop-Function -Message "[$Computer] Invalid class name, not found in current namespace" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            else
                            {
                                $Connection.ReportFailure('CimDCOM')
                                $Excluded += "CimDCOM"
                                continue sub
                            }
                        }
                    }
                    #endregion CimDCOM
                    
                    #region Wmi
                    "Wmi"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Accessing computer using WMI"
                        try
                        {
                            $parameters = @{
                                ComputerName = $Computer
                                Credential = $cred
                                ClassName = $ClassName
                                ErrorAction = 'Stop'
                            }
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $parameters["Namespace"] = $Namespace }
                            Get-WmiObject @parameters
                            
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using WMI - Success!"
                            $Connection.ReportSuccess('Wmi')
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                            continue main
                        }
                        catch
                        {
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using WMI - Failed!"
                            
                            if ($_.CategoryInfo.Reason -eq "UnauthorizedAccessException")
                            {
                                if (-not $disable_badcredentialcache) { $Connection.AddBadCredential($cred) }
                                if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                                Stop-Function -Message "[$Computer] Invalid connection credentials" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            elseif ($_.CategoryInfo.Category -eq "InvalidType")
                            {
                                Stop-Function -Message "[$Computer] Invalid class name, not found in current namespace" -Target $Computer -Continue -ContinueLabel "main" -InnerErrorRecord $_
                            }
                            else
                            {
                                $Connection.ReportFailure('Wmi')
                                $Excluded += "Wmi"
                                continue sub
                            }
                        }
                    }
                    #endregion Wmi
                    
                    #region PowerShell Remoting
                    "PowerShellRemoting"
                    {
                        try
                        {
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using PowerShell Remoting"
                            $scp_string = "Get-WmiObject -Class $ClassName -ErrorAction Stop"
                            if ($PSBoundParameters.ContainsKey("Namespace")) { $scp_string += " -Namespace $Namespace" }
                            
                            $parameters = @{
                                ScriptBlock = ([System.Management.Automation.ScriptBlock]::Create($scp_string))
                                ComputerName = $ComputerName
                            }
                            if ($Credential) { $parameters["Credential"] = $Credential }
                            Invoke-Command @parameters
                            
                            Write-Message -Level Verbose -Message "[$Computer] Accessing computer using PowerShell Remoting - Success!"
                            $Connection.ReportSuccess('PowerShellRemoting')
                            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $Connection }
                            continue main
                        }
                        catch
                        {
                            # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                            # There simply is no way to differentiate between actual authentication errors and server not reached
                            $Connection.ReportFailure('PowerShellRemoting')
                            $Excluded += "PowerShellRemoting"
                            continue sub
                        }
                    }
                    #endregion PowerShell Remoting
                }
            }
        }
    }
    End
    {
        
    }
}
