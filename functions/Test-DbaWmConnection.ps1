function Test-DbaWmConnection
{
<#
    .SYNOPSIS
        Tests over which paths a computer can be managed.
    
    .DESCRIPTION
        Tests over which paths a computer can be managed.
        
        This function tries out the connectivity for:
        - Cim over WinRM
        - Cim over DCOM
        - Wmi
        - PowerShellRemoting
        Results will be written to the connectivity cache and will cause Get-DbaWmObject and Invoke-DbaWmMethog to connect using the way most likely to succeed.
        This way, it is likely the other commands will take less time to execute. These other's too cache their results, in order to dynamically update connection statistics.
        
        Further, this function can be used to define some settings on the cached connection, such as what protocals may be tried both by test as well as subsequent connections.
    
    .PARAMETER ComputerName
        The computer to test against.
    
    .PARAMETER Credential
        The credentials to use when running the test.
        Bad credentials are automatically cached as non-working, a behavior that can be disabled by the 'Cache.Management.Disable.BadCredentialList' configuration.
    
    .PARAMETER Type
        The connection protocol types to test.
        By default, all types are tested.
        
        Available connection protocol types:
        "CimRM", "CimDCOM", "Wmi", "PowerShellRemoting"
    
    .PARAMETER ClearCache
        Clears all previously cached connection information and creates a new cache for the computer processed.
    
    .PARAMETER Force
        Overrides safeguards and "do you really want to do this" kinds of issues.
        - Will force a test to proceed on a known bad credential
    
    .PARAMETER OverrideCredential
        By default, explicitly defined credential trump stored credentials.
        Setting the specified credentials as override causes the stored credentials to be used for every connection, no matter the input.
        This can be used without credentials, in which case the default windows authentication of the current user will be used.
    
        Note: Given its nature, Test-DbaWmConnection will ignore this setting.
    
    .PARAMETER SetCredential
        Sets the specified credentials (or windows authentication, if none were) as the default credential for the connection.
        In situations where a credential is known to not work for this target, the function will then fall back to this registered credential.
        When used in combination with OverrideCredential, the thus registered credential will be prioritized before input instead.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
    .EXAMPLE
        PS C:\> Test-DbaWMConnection -ComputerName sql2014
    
        Performs a full-spectrum connection test against the computer sql2014.
        The results will be reported and registered, future calls from Get-DbaWmObject will thus recognize the results and optimize the query.
    
    .EXAMPLE
        PS C:\> Test-DbaWMConnection -ComputerName sql2014 -Credential $null -DisableConnectionType PowerShellRemoting, Wmi -OverrideCredential -SetCredential -Type CimDCOM, CimRM
    
        This test will run a connectivity test against the computer sql2014
        - It will use windows authentication of the current user
        - It will only test Cim over DCOM and Cim over WinRM
        - It will disable the use of PowerShellRemoting and WMi as a connectivity type
        - It will configure all connections to this server to use the current windows credentials, instead of what ever may be specified by the user or another function.
    
        The results will be reported and registered along with the settings, future calls from Get-DbaWmObject will thus recognize the results and optimize the query.
    
    .EXAMPLE
        PS C:\> Test-DbaWMConnection -ComputerName sql2014 -Credential $cred -ClearCache
    
        Performs a full-spectrum connection test against the computer sql2014 using the credentials stored in $cred.
        Before doing so it will discard all previous results and settings.
        The results will be reported and registered, future calls from Get-DbaWmObject will thus recognize the results and optimize the query.
    
    .NOTES
        Additional information about the function.
#>
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $ComputerName = $env:COMPUTERNAME,
        
        [System.Management.Automation.PSCredential]
        $Credential,
        
        [sqlcollective.dbatools.Connection.ManagementConnectionType[]]
        $Type = @("CimRM", "CimDCOM", "Wmi", "PowerShellRemoting"),
        
        [switch]
        $ClearCache,
        
        [switch]
        $Force,
        
        [switch]
        $OverrideCredential,
        
        [switch]
        $SetCredential,
        
        [sqlcollective.dbatools.Connection.ManagementConnectionType[]]
        $DisableConnectionType,
        
        [switch]
        $Silent
    )
    
    Begin
    {
        #region Configuration Values
        $disable_cache = Get-DbaConfigValue -Name "Cache.Management.Disable.All" -Fallback $false
        $disable_badcredentialcache = Get-DbaConfigValue -Name "Cache.Management.Disable.BadCredentialList" -Fallback $false
        #endregion Configuration Values
        
        #region Helper Functions
        function Test-ConnectionCimRM
        {
            [CmdletBinding()]
            Param (
                [string]
                $ComputerName,
                
                [System.Management.Automation.PSCredential]
                $Credential
            )
            
            try
            {
                $Session = New-CimSession -ComputerName $ComputerName -Credential $Credential -ErrorAction Stop
                $os = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem -ErrorAction Stop
                Remove-CimSession -CimSession $Session
                
                New-Object PSObject -Property @{
                    Success = $true
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
            catch
            {
                Remove-CimSession -CimSession $Session
                if ($_.CategoryInfo.Category -eq "AuthenticationError")
                {
                    New-Object PSObject -Property @{
                        Success = $false
                        Timestamp = Get-Date
                        Authenticated = $false
                    }
                }
                else
                {
                    New-Object PSObject -Property @{
                        Success = $false
                        Timestamp = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }
        
        function Test-ConnectionCimDCOM
        {
            [CmdletBinding()]
            Param (
                [string]
                $ComputerName,
                
                [System.Management.Automation.PSCredential]
                $Credential
            )
            
            try
            {
                $sessionoption = New-CimSessionOption -Protocol DCOM
                $Session = New-CimSession -ComputerName $ComputerName -Credential $Credential -SessionOption $sessionoption -ErrorAction Stop
                $os = Get-CimInstance -CimSession $Session -ClassName Win32_OperatingSystem -ErrorAction Stop
                Remove-CimSession -CimSession $Session
                
                New-Object PSObject -Property @{
                    Success = $true
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
            catch
            {
                Remove-CimSession -CimSession $Session
                if ($_.CategoryInfo.Category -eq "AuthenticationError")
                {
                    New-Object PSObject -Property @{
                        Success = $false
                        Timestamp = Get-Date
                        Authenticated = $false
                    }
                }
                else
                {
                    New-Object PSObject -Property @{
                        Success = $false
                        Timestamp = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }
        
        function Test-ConnectionWmi
        {
            [CmdletBinding()]
            Param (
                [string]
                $ComputerName,
                
                [System.Management.Automation.PSCredential]
                $Credential
            )
            
            try
            {
                $os = Get-WmiObject -ComputerName $ComputerName -Credential $Credential -Class Win32_OperatingSystem -ErrorAction Stop
                New-Object PSObject -Property @{
                    Success = $true
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
            catch [System.UnauthorizedAccessException]
            {
                New-Object PSObject -Property @{
                    Success = $false
                    Timestamp = Get-Date
                    Authenticated = $false
                }
            }
            catch
            {
                New-Object PSObject -Property @{
                    Success = $false
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
        }
        
        function Test-ConnectionPowerShellRemoting
        {
            [CmdletBinding()]
            Param (
                [string]
                $ComputerName,
                
                [System.Management.Automation.PSCredential]
                $Credential
            )
            
            try
            {
                $parameters = @{
                    ScriptBlock = { Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop }
                    ComputerName = $ComputerName
                }
                if ($Credential) { $parameters["Credential"] = $Credential }
                $os = Invoke-Command @parameters
                
                New-Object PSObject -Property @{
                    Success = $true
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
            catch
            {
                # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                # There simply is no way to differentiate between actual authentication errors and server not reached
                New-Object PSObject -Property @{
                    Success = $false
                    Timestamp = Get-Date
                    Authenticated = $true
                }
            }
        }
        #endregion Helper Functions
    }
    Process
    {
        foreach ($Computer in $ComputerName)
        {
            $Computer = $Computer.ToLower()
            Write-Message -Level VeryVerbose -Message "[$Computer] Testing management connection"
            
            #region Setup connection object
            $con = $null
            if (-not ($disable_cache -or $ClearCache)) { $con = [sqlcollective.dbatools.Connection.ConnectionHost]::Connections["$Computer"] }
            elseif ($ClearCache)
            {
                Write-Message -Level Important -Message "[$Computer] Clearing cached connections, if registered"
                if ([sqlcollective.dbatools.Connection.ConnectionHost]::Connections.ContainsKey($Computer))
                {
                    Write-Message -Message "[$Computer] Cached connection found, clearing it out" -Level VeryVerbose
                    [sqlcollective.dbatools.Connection.ConnectionHost]::Connections.Remove($Computer)
                }
                $con = New-Object -TypeName sqlcollective.dbatools.Connection.ManagementConnection
                $con.ComputerName = $Computer
            }
            
            if (-not $con)
            {
                Write-Message -Level Verbose -Message "[$Computer] No connection registered yet"
                $con = New-Object -TypeName sqlcollective.dbatools.Connection.ManagementConnection
                $con.ComputerName = $Computer
            }
            elseif (-not $ClearCache)
            {
                Write-Message -Message "[$Computer] Previous connection statistics found and retrieved" -Level Verbose
            }
            #endregion Setup connection object
            
            #region Handle credentials
            $BadCredentialsFound = $false
            if ($disable_badcredentialcache) { $con.KnownBadCredentials.Clear() }
            elseif ($con.IsBadCredential($Credential) -and (-not $Force))
            {
                Stop-Function -Message "[$Computer] The credentials supplied are on the list of known bad credentials, skipping. Use -Force to override this." -Continue -Category InvalidArgument -Target $Computer
            }
            elseif ($con.IsBadCredential($Credential) -and $Force)
            {
                $con.RemoveBadCredential($Credential)
            }
            
            if ($SetCredential) { $con.Credentials = $Credential }
            if ($OverrideCredential) { $con.OverrideInputCredentials = $OverrideCredential }
            #endregion Handle credentials
            
            if ($PSBoundParameters.ContainsKey("DisableConnectionType"))
            {
                $con.DisabledConnectionTypes = $DisableConnectionType -join ", "
            }
            
            #region Connectivity Tests
            :types foreach ($ConnectionType in $Type)
            {
                switch ($ConnectionType)
                {
                    #region CimRM
                    "CimRM"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using Cim over WinRM"
                        $res = Test-ConnectionCimRM -ComputerName $Computer -Credential $Credential
                        $con.LastCimRM = $res.Timestamp
                        $con.CimRM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] Cim over WinRM Results | Success: $($res.Success), Authentication: $($res.Authenticated)"
                        
                        if ((-not $disable_badcredentialcache) -and (-not $res.Authenticated))
                        {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimRM
                    
                    #region CimDCOM
                    "CimDCOM"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using Cim over DCOM"
                        $res = Test-ConnectionCimDCOM -ComputerName $Computer -Credential $Credential
                        $con.LastCimDCOM = $res.Timestamp
                        $con.CimDCOM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] Cim over DCOM Results | Success: $($res.Success), Authentication: $($res.Authenticated)"
                        
                        if ((-not $disable_badcredentialcache) -and (-not $res.Authenticated))
                        {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimDCOM
                    
                    #region Wmi
                    "Wmi"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using Wmi"
                        $res = Test-ConnectionWmi -ComputerName $Computer -Credential $Credential
                        $con.LastWmi = $res.Timestamp
                        $con.Wmi = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] Wmi Results | Success: $($res.Success), Authentication: $($res.Authenticated)"
                        
                        if ((-not $disable_badcredentialcache) -and (-not $res.Authenticated))
                        {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion Wmi
                    
                    #region PowerShell Remoting
                    "PowerShellRemoting"
                    {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using PowerShell Remoting"
                        $res = Test-ConnectionPowerShellRemoting -ComputerName $Computer -Credential $Credential
                        $con.LastPowerShellRemoting = $res.Timestamp
                        $con.PowerShellRemoting = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] PowerShell Remoting Results | Success: $($res.Success)"
                    }
                    #endregion PowerShell Remoting
                }
            }
            #endregion Connectivity Tests
            
            if (-not $disable_cache) { [sqlcollective.dbatools.Connection.ConnectionHost]::Connections[$Computer] = $con }
            $con
        }
    }
    End
    {
        
    }
}

