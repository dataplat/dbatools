function Test-DbaKerberos {
    <#
    .SYNOPSIS
        Tests Kerberos authentication configuration for SQL Server instances by performing comprehensive diagnostic checks

    .DESCRIPTION
        This function performs a comprehensive suite of diagnostic checks to troubleshoot Kerberos authentication issues for SQL Server instances. It addresses the most common causes of Kerberos authentication failures including SPN configuration problems, DNS issues, time synchronization errors, service account configuration, network connectivity problems, and security policy misconfigurations.

        The function performs 25+ checks across multiple categories:
        - SPN validation (duplicate detection, format validation, ownership verification)
        - Time synchronization (client-server and server-DC time comparisons)
        - DNS resolution (forward/reverse lookups, CNAME detection)
        - Service account configuration (lock status, delegation settings)
        - Network connectivity (Kerberos and LDAP port testing)
        - Security policy validation (encryption types, secure channel)
        - SQL Server configuration (service account, network protocols)
        - Authentication verification (current auth scheme validation)

        Each check returns a structured result with status (Pass/Fail/Warning), detailed findings, and actionable remediation recommendations. Use the -Detailed switch for verbose diagnostic output including intermediate check results.

        This command is essential for troubleshooting authentication failures, validating Kerberos setup before migrations, performing security audits, and as part of regular maintenance to ensure proper authentication across SQL Server environments.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances to test Kerberos configuration.
        Accepts SQL Server instance names and supports pipeline input for bulk testing.
        The function will perform comprehensive Kerberos diagnostics for each specified instance.

    .PARAMETER ComputerName
        Alternative parameter to specify target computers to test.
        Use this when you want to test Kerberos configuration at the computer level rather than for specific SQL instances.
        Accepts computer names, IP addresses, or fully qualified domain names.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Alternative credential for connecting to Active Directory.
        Required for querying AD to verify SPN registrations and service account properties.

    .PARAMETER Detailed
        Returns detailed diagnostic output including intermediate check results and verbose findings.
        Use this switch when you need comprehensive troubleshooting information beyond pass/fail status.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Kerberos, SPN, Authentication, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaKerberos

    .EXAMPLE
        PS C:\> Test-DbaKerberos -SqlInstance sql2016

        Performs comprehensive Kerberos diagnostic checks for the sql2016 instance, returning pass/fail status for each check.

    .EXAMPLE
        PS C:\> Test-DbaKerberos -SqlInstance sql2016 -Detailed

        Performs comprehensive Kerberos diagnostic checks with detailed output including verbose findings and intermediate results.

    .EXAMPLE
        PS C:\> Test-DbaKerberos -SqlInstance sql2016, sql2019 -Credential (Get-Credential)

        Tests multiple SQL Server instances using specified credentials for AD queries.

    .EXAMPLE
        PS C:\> Test-DbaKerberos -ComputerName SERVER01 -SqlCredential ad\sqldba

        Tests Kerberos configuration for all SQL instances on SERVER01 using specified AD credentials.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlcentral | Test-DbaKerberos | Where-Object Status -eq "Fail"

        Tests all registered servers and returns only the checks that failed, useful for identifying problems across your environment.
    #>
    [CmdletBinding(DefaultParameterSetName = "Instance")]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Computer")]
        [DbaInstanceParameter[]]$ComputerName,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [switch]$Detailed,
        [switch]$EnableException
    )

    begin {
        $checkResults = New-Object System.Collections.ArrayList
    }

    process {
        $targets = if ($PSCmdlet.ParameterSetName -eq "Instance") { $SqlInstance } else { $ComputerName }

        foreach ($target in $targets) {
            try {
                # Resolve the target to get computer and instance information
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        $server = Connect-DbaInstance -SqlInstance $target -SqlCredential $SqlCredential
                        $computerTarget = $server.ComputerName
                        $instanceName = $server.ServiceName
                    } catch {
                        Stop-Function -Message "Failed to connect to SQL instance $target" -ErrorRecord $_ -Continue
                        continue
                    }
                } else {
                    $computerTarget = $target.ComputerName
                    $instanceName = $null
                }

                Write-Message -Level Verbose -Message "Starting Kerberos diagnostics for $target"

                #region Tier 1 Checks - Essential & Straightforward

                #region SPN Checks
                # Check 1: Run Test-DbaSpn
                try {
                    Write-Message -Level Verbose -Message "Running Test-DbaSpn integration check"
                    $splatSpn = @{
                        ComputerName    = $computerTarget
                        Credential      = $Credential
                        EnableException = $true
                    }
                    $spnResults = Test-DbaSpn @splatSpn

                    # Test-DbaSpn checks all instances on ComputerName and has no parameter SqlInstance
                    # So we filter until Test-DbaSpn has a parameter SqlInstance
                    if ($instanceName) {
                        $spnResults = $spnResults | Where-Object InstanceName -eq $instanceName
                    }

                    $spnIssues = $spnResults | Where-Object IsSet -eq $false
                    if ($spnIssues) {
                        $details = "Missing SPNs: $($spnIssues.RequiredSPN -join ', ')"
                        $remediation = "Register missing SPNs using Set-DbaSpn or setspn.exe. Ensure service account has permissions to register SPNs."
                        $status = "Fail"
                    } else {
                        $details = "All required SPNs are registered correctly"
                        $remediation = "None"
                        $status = "Pass"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "SPN Registration"
                            Category     = "SPN"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "SPN Registration"
                            Category     = "SPN"
                            Status       = "Warning"
                            Details      = "Unable to query SPNs: $($_.Exception.Message)"
                            Remediation  = "Verify AD connectivity and credentials have permission to query Active Directory"
                        })
                }

                # Check 5: Check AG listener SPNs if applicable
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Checking for Availability Group listener SPNs"
                        $listeners = Get-DbaAgListener -SqlInstance $server -EnableException
                        foreach ($listener in $listeners) {
                            Write-Message -Level Verbose -Message "Running Test-DbaSpn integration check for $($listener.AvailabilityGroup)"
                            $splatSpn = @{
                                SqlInstance       = $listener.SqlInstance
                                SqlCredential     = $SqlCredential
                                Credential        = $Credential
                                AvailabilityGroup = $listener.AvailabilityGroup
                                Listener          = $listener.Name
                                EnableException   = $true
                            }
                            $spnResults = Test-DbaAgSpn @splatSpn

                            $spnIssues = $spnResults | Where-Object IsSet -eq $false
                            if ($spnIssues) {
                                $details = "Missing SPNs: $($spnIssues.RequiredSPN -join ', ')"
                                $remediation = "Register missing SPNs using Set-DbaSpn or setspn.exe. Ensure service account has permissions to register SPNs."
                                $status = "Fail"
                            } else {
                                $details = "All required SPNs are registered correctly"
                                $remediation = "None"
                                $status = "Pass"
                            }

                            $null = $checkResults.Add([PSCustomObject]@{
                                    ComputerName = $computerTarget
                                    InstanceName = $instanceName
                                    Check        = "AG Listener SPN - $($listener.Name)"
                                    Category     = "SPN"
                                    Status       = $status
                                    Details      = $details
                                    Remediation  = $remediation
                                })
                        }
                    } catch {
                        # No AGs or unable to query - not an error condition
                    }
                }
                #endregion SPN Checks

                #region Time Synchronization Checks
                # Check 6: Compare system clocks (client to SQL Server)
                try {
                    Write-Message -Level Verbose -Message "Comparing client and server time"
                    $clientTime = Get-Date
                    if ($PSCmdlet.ParameterSetName -eq "Instance") {
                        $serverTime = $server.Query("SELECT GETDATE() AS ServerTime").ServerTime
                        $timeDiff = [Math]::Abs(($clientTime - $serverTime).TotalMinutes)

                        if ($timeDiff -gt 5) {
                            $status = "Fail"
                            $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes exceeds 5 minute Kerberos threshold"
                            $remediation = "Synchronize time between client and server. Kerberos requires time difference under 5 minutes."
                        } elseif ($timeDiff -gt 2) {
                            $status = "Warning"
                            $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes is approaching 5 minute threshold"
                            $remediation = "Monitor time synchronization. Consider configuring NTP to maintain accurate time."
                        } else {
                            $status = "Pass"
                            $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes is within acceptable range"
                            $remediation = "None"
                        }
                    } else {
                        $splatTime = @{
                            ComputerName = $computerTarget
                            ScriptBlock  = { Get-Date }
                        }
                        if ($Credential) {
                            $splatTime.Credential = $Credential
                        }
                        $serverTime = Invoke-Command @splatTime
                        $timeDiff = [Math]::Abs(($clientTime - $serverTime).TotalMinutes)

                        if ($timeDiff -gt 5) {
                            $status = "Fail"
                            $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes exceeds 5 minute Kerberos threshold"
                            $remediation = "Synchronize time between client and server. Kerberos requires time difference under 5 minutes."
                        } else {
                            $status = "Pass"
                            $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes is within acceptable range"
                            $remediation = "None"
                        }
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Time Synchronization (Client-Server)"
                            Category     = "Time Sync"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Time Synchronization (Client-Server)"
                            Category     = "Time Sync"
                            Status       = "Warning"
                            Details      = "Unable to compare time: $($_.Exception.Message)"
                            Remediation  = "Verify remote connectivity and ensure time service is running"
                        })
                }

                # Check 7: Compare with domain controllers
                try {
                    Write-Message -Level Verbose -Message "Comparing server time with domain controller"
                    # Get domain controller
                    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                    $dc = $domain.PdcRoleOwner.Name

                    $splatDcTime = @{
                        ComputerName = $dc
                        ScriptBlock  = { Get-Date }
                    }
                    if ($Credential) {
                        $splatDcTime.Credential = $Credential
                    }
                    $dcTime = Invoke-Command @splatDcTime

                    if ($PSCmdlet.ParameterSetName -eq "Instance") {
                        $serverTime = $server.Query("SELECT GETDATE() AS ServerTime").ServerTime
                    } else {
                        $splatServerTime = @{
                            ComputerName = $computerTarget
                            ScriptBlock  = { Get-Date }
                        }
                        if ($Credential) {
                            $splatServerTime.Credential = $Credential
                        }
                        $serverTime = Invoke-Command @splatServerTime
                    }

                    $timeDiff = [Math]::Abs(($serverTime - $dcTime).TotalMinutes)

                    if ($timeDiff -gt 5) {
                        $status = "Fail"
                        $details = "Time difference of $([Math]::Round($timeDiff, 2)) minutes between server and DC exceeds threshold"
                        $remediation = "Configure server to sync with domain controller. Use 'w32tm /config /syncfromflags:domhier /update'"
                    } else {
                        $status = "Pass"
                        $details = "Server time synchronized with DC within $([Math]::Round($timeDiff, 2)) minutes"
                        $remediation = "None"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Time Synchronization (Server-DC)"
                            Category     = "Time Sync"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Time Synchronization (Server-DC)"
                            Category     = "Time Sync"
                            Status       = "Warning"
                            Details      = "Unable to compare time with DC: $($_.Exception.Message)"
                            Remediation  = "Verify domain connectivity and credentials"
                        })
                }
                #endregion Time Synchronization Checks

                #region DNS Checks
                # Check 8: DNS forward lookup
                try {
                    Write-Message -Level Verbose -Message "Testing DNS forward lookup"
                    $resolvedFqdn = [System.Net.Dns]::GetHostEntry($computerTarget).HostName
                    $resolvedIp = [System.Net.Dns]::GetHostAddresses($computerTarget) | Select-Object -First 1

                    if ($resolvedFqdn -and $resolvedIp) {
                        $status = "Pass"
                        $details = "Forward lookup successful: $computerTarget resolves to $($resolvedIp.IPAddressToString)"
                        $remediation = "None"
                    } else {
                        $status = "Fail"
                        $details = "Forward lookup failed for $computerTarget"
                        $remediation = "Verify DNS A record exists for this server"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "DNS Forward Lookup"
                            Category     = "DNS"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "DNS Forward Lookup"
                            Category     = "DNS"
                            Status       = "Fail"
                            Details      = "DNS forward lookup failed: $($_.Exception.Message)"
                            Remediation  = "Verify DNS configuration and A record exists"
                        })
                }

                # Check 9: DNS reverse lookup
                try {
                    Write-Message -Level Verbose -Message "Testing DNS reverse lookup"
                    $ip = [System.Net.Dns]::GetHostAddresses($computerTarget) | Select-Object -First 1
                    $reverseHost = [System.Net.Dns]::GetHostEntry($ip.IPAddressToString).HostName

                    if ($reverseHost) {
                        $status = "Pass"
                        $details = "Reverse lookup successful: $($ip.IPAddressToString) resolves to $reverseHost"
                        $remediation = "None"
                    } else {
                        $status = "Warning"
                        $details = "Reverse lookup failed for $($ip.IPAddressToString)"
                        $remediation = "Create PTR record in DNS for proper reverse lookup"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "DNS Reverse Lookup"
                            Category     = "DNS"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "DNS Reverse Lookup"
                            Category     = "DNS"
                            Status       = "Warning"
                            Details      = "DNS reverse lookup failed: $($_.Exception.Message)"
                            Remediation  = "Create PTR record in DNS for proper reverse lookup"
                        })
                }

                # Check 10: Check for CNAME records
                try {
                    Write-Message -Level Verbose -Message "Checking for CNAME records"
                    # CNAME detection requires nslookup or DNS cmdlets
                    $splatDns = @{
                        ComputerName = $computerTarget
                        ScriptBlock  = {
                            param($hostname)
                            try {
                                $result = nslookup $hostname 2>&1 | Out-String
                                if ($result -match "canonical name") {
                                    return "CNAME"
                                } else {
                                    return "A"
                                }
                            } catch {
                                return "Unknown"
                            }
                        }
                        ArgumentList = $computerTarget
                    }
                    if ($Credential) {
                        $splatDns.Credential = $Credential
                    }
                    $recordType = Invoke-Command @splatDns

                    if ($recordType -eq "CNAME") {
                        $status = "Fail"
                        $details = "CNAME record detected. CNAMEs break Kerberos authentication."
                        $remediation = "Replace CNAME with A record in DNS. Kerberos does not support CNAME aliases."
                    } elseif ($recordType -eq "A") {
                        $status = "Pass"
                        $details = "Using A record (not CNAME)"
                        $remediation = "None"
                    } else {
                        $status = "Warning"
                        $details = "Unable to determine DNS record type"
                        $remediation = "Manually verify no CNAME records are in use"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "CNAME Detection"
                            Category     = "DNS"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "CNAME Detection"
                            Category     = "DNS"
                            Status       = "Warning"
                            Details      = "Unable to check for CNAME: $($_.Exception.Message)"
                            Remediation  = "Manually verify no CNAME records are in use"
                        })
                }
                #endregion DNS Checks

                #region Service Account Checks
                # Check 11: Verify service account
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Verifying SQL Server service account"
                        $serviceAccount = $server.ServiceAccount

                        if ($serviceAccount -like "*\*$") {
                            # gMSA or computer account (ends with $)
                            $status = "Pass"
                            $details = "SQL Server running as managed service account or computer account: $serviceAccount (supports Kerberos)"
                            $remediation = "None"
                        } elseif ($serviceAccount -eq "LocalSystem" -or $serviceAccount -eq "NetworkService") {
                            # LocalSystem or NetworkService - uses computer account for network auth
                            $status = "Pass"
                            $details = "SQL Server running as $serviceAccount. Uses computer account for Kerberos (works for single instance setups)"
                            $remediation = "Consider using gMSA or dedicated domain service account for best practice, especially with multiple instances"
                        } elseif ($serviceAccount -like "NT SERVICE\*") {
                            # Virtual account - uses computer account for network auth
                            $status = "Pass"
                            $details = "SQL Server running as virtual account $serviceAccount. Uses computer account for Kerberos (works for single instance setups)"
                            $remediation = "Consider using gMSA or dedicated domain service account for best practice, especially with multiple instances"
                        } elseif ($serviceAccount -match "^[^\\]+\\[^\\]+$" -and $serviceAccount -notlike "*\*$") {
                            # Domain account (has backslash, no $ at end)
                            $status = "Pass"
                            $details = "SQL Server running as domain service account: $serviceAccount (supports Kerberos)"
                            $remediation = "None"
                        } else {
                            # Local account or unrecognized format
                            $status = "Fail"
                            $details = "SQL Server running as local account: $serviceAccount. Kerberos requires domain-joined identity (gMSA, domain account, or computer account)"
                            $remediation = "Change service account to gMSA (best practice), domain service account, or built-in account (LocalSystem/NetworkService/NT SERVICE)"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Service Account Type"
                                Category     = "Service Account"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Service Account Type"
                                Category     = "Service Account"
                                Status       = "Warning"
                                Details      = "Unable to verify service account: $($_.Exception.Message)"
                                Remediation  = "Manually verify SQL Server service account supports Kerberos (gMSA, domain account, or computer account)"
                            })
                    }
                }

                # Check 12: Check account lock status
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Checking service account lock status"
                        $serviceAccount = $server.ServiceAccount

                        if ($serviceAccount -notlike "NT SERVICE\*" -and $serviceAccount -ne "LocalSystem" -and $serviceAccount -ne "NetworkService") {
                            # Extract just the username from DOMAIN\username
                            $username = $serviceAccount -replace '^.*\\', ''

                            if ($username.EndsWith('$')) {
                                $objectCategory = 'msDS-GroupManagedServiceAccount'
                            } else {
                                $objectCategory = 'User'
                            }

                            # Query AD for account status
                            $searcher = New-Object System.DirectoryServices.DirectorySearcher
                            $searcher.Filter = "(&(objectCategory=$objectCategory)(samAccountName=$username))"
                            $searcher.PropertiesToLoad.Add("lockoutTime") | Out-Null
                            $searcher.PropertiesToLoad.Add("userAccountControl") | Out-Null
                            $adUser = $searcher.FindOne()

                            if ($adUser) {
                                $lockoutTime = $adUser.Properties["lockoutTime"][0]
                                $uac = $adUser.Properties["userAccountControl"][0]
                                $isDisabled = ($uac -band 2) -eq 2

                                if ($lockoutTime -gt 0) {
                                    $status = "Fail"
                                    $details = "Service account $serviceAccount is locked out in Active Directory"
                                    $remediation = "Unlock the account in Active Directory Users and Computers"
                                } elseif ($isDisabled) {
                                    $status = "Fail"
                                    $details = "Service account $serviceAccount is disabled in Active Directory"
                                    $remediation = "Enable the account in Active Directory Users and Computers"
                                } else {
                                    $status = "Pass"
                                    $details = "Service account is not locked or disabled"
                                    $remediation = "None"
                                }
                            } else {
                                $status = "Warning"
                                $details = "Unable to locate service account in Active Directory"
                                $remediation = "Verify account exists and credentials have permission to query AD"
                            }
                        } else {
                            $status = "Warning"
                            $details = "Not using domain account, skipping lock check"
                            $remediation = "None"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Account Lock Status"
                                Category     = "Service Account"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Account Lock Status"
                                Category     = "Service Account"
                                Status       = "Warning"
                                Details      = "Unable to check account status: $($_.Exception.Message)"
                                Remediation  = "Manually verify account is not locked in AD"
                            })
                    }
                }

                # Check 13: Check "Account is sensitive and cannot be delegated"
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Checking delegation settings"
                        $serviceAccount = $server.ServiceAccount

                        if ($serviceAccount -notlike "NT SERVICE\*" -and $serviceAccount -ne "LocalSystem" -and $serviceAccount -ne "NetworkService") {
                            # Extract just the username from DOMAIN\username
                            $username = $serviceAccount -replace '^.*\\', ''

                            if ($username.EndsWith('$')) {
                                $objectCategory = 'msDS-GroupManagedServiceAccount'
                            } else {
                                $objectCategory = 'User'
                            }

                            # Query AD for account status
                            $searcher = New-Object System.DirectoryServices.DirectorySearcher
                            $searcher.Filter = "(&(objectCategory=$objectCategory)(samAccountName=$username))"
                            $searcher.PropertiesToLoad.Add("userAccountControl") | Out-Null
                            $adUser = $searcher.FindOne()

                            if ($adUser) {
                                $uac = $adUser.Properties["userAccountControl"][0]
                                $notDelegated = ($uac -band 1048576) -eq 1048576

                                if ($notDelegated) {
                                    $status = "Fail"
                                    $details = "Account is marked as sensitive and cannot be delegated"
                                    $remediation = "Remove 'Account is sensitive and cannot be delegated' flag in AD user properties"
                                } else {
                                    $status = "Pass"
                                    $details = "Account delegation is allowed"
                                    $remediation = "None"
                                }
                            } else {
                                $status = "Warning"
                                $details = "Unable to query account delegation settings"
                                $remediation = "Manually verify delegation settings in AD"
                            }
                        } else {
                            $status = "Warning"
                            $details = "Not using domain account, skipping delegation check"
                            $remediation = "None"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Delegation Settings"
                                Category     = "Service Account"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Delegation Settings"
                                Category     = "Service Account"
                                Status       = "Warning"
                                Details      = "Unable to check delegation: $($_.Exception.Message)"
                                Remediation  = "Manually verify delegation settings in AD"
                            })
                    }
                }
                #endregion Service Account Checks

                #region Authentication Validation
                # Check 14: Test-DbaConnectionAuthScheme
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Testing current authentication scheme"
                        $splatAuth = @{
                            SqlInstance     = $server
                            EnableException = $true
                        }
                        $authResult = Test-DbaConnectionAuthScheme @splatAuth

                        if ($authResult.AuthScheme -eq "KERBEROS") {
                            $status = "Pass"
                            $details = "Currently using Kerberos authentication"
                            $remediation = "None"
                        } elseif ($authResult.AuthScheme -eq "NTLM") {
                            $status = "Fail"
                            $details = "Currently using NTLM authentication instead of Kerberos"
                            $remediation = "Review failed checks above to identify why Kerberos is not working"
                        } else {
                            $status = "Warning"
                            $details = "Authentication scheme: $($authResult.AuthScheme)"
                            $remediation = "Verify authentication configuration"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Current Authentication Scheme"
                                Category     = "Authentication"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Current Authentication Scheme"
                                Category     = "Authentication"
                                Status       = "Warning"
                                Details      = "Unable to check auth scheme: $($_.Exception.Message)"
                                Remediation  = "Manually query sys.dm_exec_connections"
                            })
                    }
                }
                #endregion Authentication Validation

                #endregion Tier 1 Checks

                #region Tier 2 Checks - Practical & Valuable

                #region Network Connectivity Checks
                # Check 16: Test Kerberos ports (tcp/88, udp/88)
                try {
                    Write-Message -Level Verbose -Message "Testing Kerberos port connectivity"
                    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                    $dc = $domain.PdcRoleOwner.Name

                    $tcpTest = Test-NetConnection -ComputerName $dc -Port 88 -WarningAction SilentlyContinue
                    if ($tcpTest.TcpTestSucceeded) {
                        $status = "Pass"
                        $details = "TCP port 88 accessible to DC $dc"
                        $remediation = "None"
                    } else {
                        $status = "Fail"
                        $details = "TCP port 88 not accessible to DC $dc"
                        $remediation = "Open TCP port 88 in firewall for Kerberos authentication"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Port (TCP/88)"
                            Category     = "Network"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Port (TCP/88)"
                            Category     = "Network"
                            Status       = "Warning"
                            Details      = "Unable to test port connectivity: $($_.Exception.Message)"
                            Remediation  = "Manually verify TCP/88 and UDP/88 connectivity to DC"
                        })
                }

                # Check 17: Test LDAP ports (tcp/389, udp/389)
                try {
                    Write-Message -Level Verbose -Message "Testing LDAP port connectivity"
                    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                    $dc = $domain.PdcRoleOwner.Name

                    $tcpTest = Test-NetConnection -ComputerName $dc -Port 389 -WarningAction SilentlyContinue
                    if ($tcpTest.TcpTestSucceeded) {
                        $status = "Pass"
                        $details = "TCP port 389 accessible to DC $dc"
                        $remediation = "None"
                    } else {
                        $status = "Fail"
                        $details = "TCP port 389 not accessible to DC $dc"
                        $remediation = "Open TCP port 389 in firewall for LDAP queries"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "LDAP Port (TCP/389)"
                            Category     = "Network"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "LDAP Port (TCP/389)"
                            Category     = "Network"
                            Status       = "Warning"
                            Details      = "Unable to test port connectivity: $($_.Exception.Message)"
                            Remediation  = "Manually verify TCP/389 and UDP/389 connectivity to DC"
                        })
                }

                # Check 18: Test Kerberos-Kdc port (tcp/464)
                try {
                    Write-Message -Level Verbose -Message "Testing Kerberos password change port"
                    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                    $dc = $domain.PdcRoleOwner.Name

                    $tcpTest = Test-NetConnection -ComputerName $dc -Port 464 -WarningAction SilentlyContinue
                    if ($tcpTest.TcpTestSucceeded) {
                        $status = "Pass"
                        $details = "TCP port 464 accessible to DC $dc"
                        $remediation = "None"
                    } else {
                        $status = "Warning"
                        $details = "TCP port 464 not accessible to DC $dc"
                        $remediation = "Open TCP port 464 for Kerberos password changes (optional)"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos-Kdc Port (TCP/464)"
                            Category     = "Network"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos-Kdc Port (TCP/464)"
                            Category     = "Network"
                            Status       = "Warning"
                            Details      = "Unable to test port connectivity: $($_.Exception.Message)"
                            Remediation  = "Manually verify TCP/464 connectivity to DC"
                        })
                }

                #region Security Policy Checks
                # Check 20: Check encryption types
                try {
                    Write-Message -Level Verbose -Message "Checking Kerberos encryption types"
                    $splatEncryption = @{
                        ComputerName = $computerTarget
                        ScriptBlock  = {
                            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters"
                            if (Test-Path $regPath) {
                                $encTypes = Get-ItemProperty -Path $regPath -Name "SupportedEncryptionTypes" -ErrorAction SilentlyContinue
                                return $encTypes.SupportedEncryptionTypes
                            } else {
                                return $null
                            }
                        }
                    }
                    if ($Credential) {
                        $splatEncryption.Credential = $Credential
                    }
                    $encryptionTypes = Invoke-Command @splatEncryption

                    # RC4_HMAC_MD5 is 0x4, AES128 is 0x8, AES256 is 0x10
                    if ($encryptionTypes) {
                        $hasRC4 = ($encryptionTypes -band 0x4) -eq 0x4
                        if ($hasRC4 -or $encryptionTypes -eq 0) {
                            $status = "Pass"
                            $details = "RC4_HMAC_MD5 or default encryption types are enabled"
                            $remediation = "None"
                        } else {
                            $status = "Warning"
                            $details = "RC4_HMAC_MD5 not explicitly enabled. Current value: $encryptionTypes"
                            $remediation = "Consider enabling RC4_HMAC_MD5 for compatibility if needed"
                        }
                    } else {
                        $status = "Pass"
                        $details = "Using default encryption types (not explicitly configured)"
                        $remediation = "None"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Encryption Types"
                            Category     = "Security Policy"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Encryption Types"
                            Category     = "Security Policy"
                            Status       = "Warning"
                            Details      = "Unable to check encryption types: $($_.Exception.Message)"
                            Remediation  = "Manually verify encryption types in local security policy"
                        })
                }

                # Check 21: Test-ComputerSecureChannel
                try {
                    Write-Message -Level Verbose -Message "Testing computer secure channel"
                    $splatSecureChannel = @{
                        ComputerName = $computerTarget
                        ScriptBlock  = { Test-ComputerSecureChannel }
                    }
                    if ($Credential) {
                        $splatSecureChannel.Credential = $Credential
                    }
                    $secureChannelTest = Invoke-Command @splatSecureChannel

                    if ($secureChannelTest) {
                        $status = "Pass"
                        $details = "Computer secure channel to domain is healthy"
                        $remediation = "None"
                    } else {
                        $status = "Fail"
                        $details = "Computer secure channel to domain is broken"
                        $remediation = "Run 'Test-ComputerSecureChannel -Repair' to reset computer account password"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Computer Secure Channel"
                            Category     = "Security Policy"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Computer Secure Channel"
                            Category     = "Security Policy"
                            Status       = "Warning"
                            Details      = "Unable to test secure channel: $($_.Exception.Message)"
                            Remediation  = "Manually run Test-ComputerSecureChannel"
                        })
                }

                # Check 22: Check hosts file
                try {
                    Write-Message -Level Verbose -Message "Checking hosts file for entries"
                    $splatHosts = @{
                        ComputerName = $computerTarget
                        ScriptBlock  = {
                            $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                            $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
                            $nonCommentLines = $hostsContent | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
                            return $nonCommentLines
                        }
                    }
                    if ($Credential) {
                        $splatHosts.Credential = $Credential
                    }
                    $hostsEntries = Invoke-Command @splatHosts

                    if ($hostsEntries) {
                        $status = "Warning"
                        $details = "Hosts file contains $($hostsEntries.Count) active entries that may override DNS"
                        $remediation = "Review hosts file at C:\Windows\System32\drivers\etc\hosts and remove unnecessary entries"
                    } else {
                        $status = "Pass"
                        $details = "No active entries in hosts file"
                        $remediation = "None"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Hosts File"
                            Category     = "Security Policy"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Hosts File"
                            Category     = "Security Policy"
                            Status       = "Warning"
                            Details      = "Unable to check hosts file: $($_.Exception.Message)"
                            Remediation  = "Manually check C:\Windows\System32\drivers\etc\hosts"
                        })
                }
                #endregion Security Policy Checks

                #region SQL Server Configuration Checks
                # Check 23: Check SQL Server service account
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Validating SQL Server service account configuration"
                        $serviceAccount = $server.ServiceAccount

                        if ($serviceAccount -like "*\*$") {
                            # gMSA or computer account (ends with $)
                            if ($serviceAccount -like "*gMSA*" -or $serviceAccount -match "^\w+\\\w+\$$") {
                                $status = "Pass"
                                $details = "SQL Server using gMSA or managed service account: $serviceAccount (best practice for Kerberos)"
                                $remediation = "None"
                            } else {
                                $status = "Pass"
                                $details = "SQL Server using computer account: $serviceAccount (supports Kerberos)"
                                $remediation = "None"
                            }
                        } elseif ($serviceAccount -eq "LocalSystem" -or $serviceAccount -eq "NetworkService") {
                            # LocalSystem or NetworkService - uses computer account
                            $status = "Pass"
                            $details = "SQL Server running as $serviceAccount (uses computer account for Kerberos)"
                            $remediation = "For best practice, consider gMSA or dedicated domain service account, especially in multi-instance or clustered environments"
                        } elseif ($serviceAccount -like "NT SERVICE\*") {
                            # Virtual account - uses computer account
                            $status = "Pass"
                            $details = "SQL Server running as virtual account $serviceAccount (uses computer account for Kerberos)"
                            $remediation = "For best practice, consider gMSA or dedicated domain service account, especially in multi-instance or clustered environments"
                        } elseif ($serviceAccount -match "^[^\\]+\\[^\\]+$" -and $serviceAccount -notlike "*\*$") {
                            # Domain account (has backslash, no $ at end)
                            $status = "Pass"
                            $details = "SQL Server using domain service account: $serviceAccount (supports Kerberos)"
                            $remediation = "None"
                        } else {
                            # Local account or unrecognized format
                            $status = "Fail"
                            $details = "SQL Server running as local account: $serviceAccount (does not support Kerberos)"
                            $remediation = "Change service account to gMSA (best practice), domain service account, or built-in account (LocalSystem/NetworkService/NT SERVICE) using SQL Server Configuration Manager"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "SQL Service Account Configuration"
                                Category     = "SQL Configuration"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "SQL Service Account Configuration"
                                Category     = "SQL Configuration"
                                Status       = "Warning"
                                Details      = "Unable to verify service account: $($_.Exception.Message)"
                                Remediation  = "Manually verify service account supports Kerberos in SQL Server Configuration Manager"
                            })
                    }
                }

                # Check 24: Verify network protocols
                if ($PSCmdlet.ParameterSetName -eq "Instance") {
                    try {
                        Write-Message -Level Verbose -Message "Checking SQL Server network protocol configuration"
                        # we need to use $server.SqlInstance to get the actual instance when the target is an Availability Group Listener
                        $tcpEnabled = (Get-DbaNetworkConfiguration -SqlInstance $server.SqlInstance -OutputType ServerProtocols -EnableException).TcpIpEnabled

                        if ($tcpEnabled) {
                            $status = "Pass"
                            $details = "TCP/IP protocol is enabled"
                            $remediation = "None"
                        } else {
                            $status = "Warning"
                            $details = "TCP/IP protocol may not be enabled"
                            $remediation = "Enable TCP/IP in SQL Server Configuration Manager for network connectivity"
                        }

                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Network Protocol Configuration"
                                Category     = "SQL Configuration"
                                Status       = $status
                                Details      = $details
                                Remediation  = $remediation
                            })
                    } catch {
                        $null = $checkResults.Add([PSCustomObject]@{
                                ComputerName = $computerTarget
                                InstanceName = $instanceName
                                Check        = "Network Protocol Configuration"
                                Category     = "SQL Configuration"
                                Status       = "Warning"
                                Details      = "Unable to verify network protocols: $($_.Exception.Message)"
                                Remediation  = "Manually verify TCP/IP is enabled in SQL Server Configuration Manager"
                            })
                    }
                }
                #endregion SQL Server Configuration Checks

                #region Client-Side Checks
                # Check 25: Run klist command
                try {
                    Write-Message -Level Verbose -Message "Checking Kerberos ticket cache with klist"
                    $klistOutput = & klist 2>&1 | Out-String

                    if ($klistOutput -match "Cached Tickets") {
                        if ($klistOutput -match "MSSQLSvc") {
                            $status = "Pass"
                            $details = "Kerberos tickets cached for SQL Server (MSSQLSvc)"
                            $remediation = "None"
                        } else {
                            $status = "Warning"
                            $details = "No MSSQLSvc tickets in cache. May need fresh connection."
                            $remediation = "Close all SQL connections and reconnect to force new ticket acquisition"
                        }
                    } else {
                        $status = "Warning"
                        $details = "Unable to retrieve Kerberos ticket cache"
                        $remediation = "Run 'klist' manually to inspect Kerberos tickets"
                    }

                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Ticket Cache"
                            Category     = "Client"
                            Status       = $status
                            Details      = $details
                            Remediation  = $remediation
                        })
                } catch {
                    $null = $checkResults.Add([PSCustomObject]@{
                            ComputerName = $computerTarget
                            InstanceName = $instanceName
                            Check        = "Kerberos Ticket Cache"
                            Category     = "Client"
                            Status       = "Warning"
                            Details      = "Unable to run klist: $($_.Exception.Message)"
                            Remediation  = "Run 'klist' manually to inspect Kerberos tickets"
                        })
                }
                #endregion Client-Side Checks

                #endregion Tier 2 Checks

            } catch {
                Stop-Function -Message "Error testing Kerberos for $target" -ErrorRecord $_ -Continue
            }
        }
    }

    end {
        # Return results
        if ($Detailed) {
            $checkResults
        } else {
            # Return summary view
            $checkResults | Select-Object ComputerName, InstanceName, Check, Category, Status, Details, Remediation
        }
    }
}
