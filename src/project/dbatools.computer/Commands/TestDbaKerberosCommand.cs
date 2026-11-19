#nullable enable
#pragma warning disable CA1416 // Windows-only command: Active Directory, DirectorySearcher, klist, WSMan remoting

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Runs a battery of Kerberos diagnostics (SPNs, time sync, DNS, service account, authentication,
/// DC connectivity, security policy, SQL configuration, ticket cache) against a SQL instance or
/// computer. Port of public/Test-DbaKerberos.ps1; surface pinned by
/// migration/baselines/Test-DbaKerberos.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaKerberos", DefaultParameterSetName = "Instance")]
public sealed class TestDbaKerberosCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Instance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>The target computer(s) for computer-level diagnostics.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Computer")]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Credential for SQL Server authentication.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Credential for Windows/remoting operations.</summary>
    [Parameter]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private bool IsInstanceSet => string.Equals(ParameterSetName, "Instance", StringComparison.OrdinalIgnoreCase);

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        DbaInstanceParameter[] targets = (IsInstanceSet ? SqlInstance : ComputerName) ?? Array.Empty<DbaInstanceParameter>();

        foreach (DbaInstanceParameter target in targets)
        {
            try
            {
                PSObject? server = null;
                string? computerTarget;
                string? instanceName;

                if (IsInstanceSet)
                {
                    try
                    {
                        Hashtable splatConnect = new Hashtable
                        {
                            { "SqlInstance", target },
                            { "SqlCredential", SqlCredential }
                        };
                        Collection<PSObject> connected = NestedCommand.Invoke(this, "Connect-DbaInstance", splatConnect);
                        server = connected.Count > 0 ? connected[0] : null;
                        computerTarget = PsString(GetProperty(server, "ComputerName"));
                        instanceName = PsString(GetProperty(server, "ServiceName"));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (RuntimeException rex)
                    {
                        StopFunction($"Failed to connect to SQL instance {target}", errorRecord: rex.ErrorRecord, continueLoop: true);
                        continue;
                    }
                    catch (Exception ex)
                    {
                        StopFunction($"Failed to connect to SQL instance {target}", exception: ex, continueLoop: true);
                        continue;
                    }
                }
                else
                {
                    computerTarget = target.ComputerName;
                    instanceName = null;
                }

                WriteMessage(MessageLevel.Verbose, $"Starting Kerberos diagnostics for {target}");

                #region SPN Checks
                // Check 1: Run Test-DbaSpn
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Running Test-DbaSpn integration check");
                    Hashtable splatSpn = new Hashtable
                    {
                        { "ComputerName", computerTarget },
                        { "Credential", Credential },
                        { "EnableException", true }
                    };
                    object? spnResults = Shape(NestedCommand.Invoke(this, "Test-DbaSpn", splatSpn));

                    // PS: Test-DbaSpn checks all instances on ComputerName and has no parameter SqlInstance
                    // So we filter until Test-DbaSpn has a parameter SqlInstance
                    if (LanguagePrimitives.IsTrue(instanceName))
                    {
                        spnResults = WhereProperty(spnResults, "InstanceName", instanceName);
                    }

                    object? spnIssues = WhereProperty(spnResults, "IsSet", false);
                    string details;
                    string remediation;
                    string status;
                    if (LanguagePrimitives.IsTrue(spnIssues))
                    {
                        details = $"Missing SPNs: {JoinMemberValues(spnIssues, "RequiredSPN", ", ")}";
                        remediation = "Register missing SPNs using Set-DbaSpn or setspn.exe. Ensure service account has permissions to register SPNs.";
                        status = "Fail";
                    }
                    else
                    {
                        details = "All required SPNs are registered correctly";
                        remediation = "None";
                        status = "Pass";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "SPN Registration", "SPN", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "SPN Registration", "SPN", "Warning",
                        $"Unable to query SPNs: {PsExceptionMessage(ex)}",
                        "Verify AD connectivity and credentials have permission to query Active Directory"));
                }

                // Check 2: Check AG listener SPNs if applicable
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Checking for Availability Group listener SPNs");
                        Hashtable splatListeners = new Hashtable
                        {
                            { "SqlInstance", server },
                            { "EnableException", true }
                        };
                        Collection<PSObject> listeners = NestedCommand.Invoke(this, "Get-DbaAgListener", splatListeners);
                        foreach (PSObject listener in listeners)
                        {
                            if (listener is null)
                            {
                                continue;
                            }
                            WriteMessage(MessageLevel.Verbose, $"Running Test-DbaSpn integration check for {PsString(GetProperty(listener, "AvailabilityGroup"))}");
                            Hashtable splatAgSpn = new Hashtable
                            {
                                { "SqlInstance", GetProperty(listener, "SqlInstance") },
                                { "SqlCredential", SqlCredential },
                                { "Credential", Credential },
                                { "AvailabilityGroup", GetProperty(listener, "AvailabilityGroup") },
                                { "Listener", GetProperty(listener, "Name") },
                                { "EnableException", true }
                            };
                            object? agSpnResults = Shape(NestedCommand.Invoke(this, "Test-DbaAgSpn", splatAgSpn));

                            object? spnIssues = WhereProperty(agSpnResults, "IsSet", false);
                            string details;
                            string remediation;
                            string status;
                            if (LanguagePrimitives.IsTrue(spnIssues))
                            {
                                details = $"Missing SPNs: {JoinMemberValues(spnIssues, "RequiredSPN", ", ")}";
                                remediation = "Register missing SPNs using Set-DbaSpn or setspn.exe. Ensure service account has permissions to register SPNs.";
                                status = "Fail";
                            }
                            else
                            {
                                details = "All required SPNs are registered correctly";
                                remediation = "None";
                                status = "Pass";
                            }

                            WriteObject(BuildCheck(computerTarget, instanceName, $"AG Listener SPN - {PsString(GetProperty(listener, "Name"))}", "SPN", status, details, remediation));
                        }
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch
                    {
                        // No AGs or unable to query - not an error condition
                    }
                }
                #endregion SPN Checks

                #region Time Synchronization Checks
                // Check 3: Compare system clocks (client to SQL Server)
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Comparing client and server time");
                    DateTime clientTime = DateTime.Now;
                    string status;
                    string details;
                    string remediation;
                    if (IsInstanceSet)
                    {
                        object? serverTimeValue = GetMemberOfResult(InvokeMethod(server, "Query", "SELECT GETDATE() AS ServerTime"), "ServerTime");
                        DateTime serverTime = LanguagePrimitives.ConvertTo<DateTime>(serverTimeValue);
                        double timeDiff = Math.Abs((clientTime - serverTime).TotalMinutes);

                        if (timeDiff > 5)
                        {
                            status = "Fail";
                            details = $"Time difference of {PsString(Math.Round(timeDiff, 2))} minutes exceeds 5 minute Kerberos threshold";
                            remediation = "Synchronize time between client and server. Kerberos requires time difference under 5 minutes.";
                        }
                        else if (timeDiff > 2)
                        {
                            status = "Warning";
                            details = $"Time difference of {PsString(Math.Round(timeDiff, 2))} minutes is approaching 5 minute threshold";
                            remediation = "Monitor time synchronization. Consider configuring NTP to maintain accurate time.";
                        }
                        else
                        {
                            status = "Pass";
                            details = $"Time difference of {PsString(Math.Round(timeDiff, 2))} minutes is within acceptable range";
                            remediation = "None";
                        }
                    }
                    else
                    {
                        object? serverTimeValue = Shape(InvokeRemoteCommand(computerTarget, "Get-Date", null, Credential));
                        DateTime serverTime = LanguagePrimitives.ConvertTo<DateTime>(serverTimeValue);
                        double timeDiff = Math.Abs((clientTime - serverTime).TotalMinutes);

                        if (timeDiff > 5)
                        {
                            status = "Fail";
                            details = $"Time difference of {PsString(Math.Round(timeDiff, 2))} minutes exceeds 5 minute Kerberos threshold";
                            remediation = "Synchronize time between client and server. Kerberos requires time difference under 5 minutes.";
                        }
                        else
                        {
                            status = "Pass";
                            details = $"Time difference of {PsString(Math.Round(timeDiff, 2))} minutes is within acceptable range";
                            remediation = "None";
                        }
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Time Synchronization (Client-Server)", "Time Sync", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Time Synchronization (Client-Server)", "Time Sync", "Warning",
                        $"Unable to compare time: {PsExceptionMessage(ex)}",
                        "Verify remote connectivity and ensure time service is running"));
                }

                // Check 4: Compare with domain controllers
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Comparing server time with domain controller");
                    // Get domain controller
                    System.DirectoryServices.ActiveDirectory.Domain domain = System.DirectoryServices.ActiveDirectory.Domain.GetCurrentDomain();
                    string dc = domain.PdcRoleOwner.Name;

                    // Get server time
                    object? serverTimeValue;
                    if (IsInstanceSet)
                    {
                        serverTimeValue = GetMemberOfResult(InvokeMethod(server, "Query", "SELECT GETDATE() AS ServerTime"), "ServerTime");
                    }
                    else
                    {
                        serverTimeValue = Shape(InvokeRemoteCommand(computerTarget, "Get-Date", null, Credential));
                    }

                    // Try w32tm first (works without admin access), fall back to Invoke-Command if needed
                    object? dcTime = null;
                    double? timeDiff = null;

                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Attempting to query DC time using w32tm");
                        // Use w32tm /stripchart to get time difference from DC without requiring PSRemoting
                        string w32tmScript = @"
                                param($dcName)
                                # Run w32tm /stripchart for 1 sample to get time offset
                                $w32tmOutput = & w32tm /stripchart /computer:$dcName /samples:1 /dataonly 2>&1 | Out-String
                                # Parse output like: ""23:59:59, +00.0012345s"" or ""23:59:59, -00.0012345s""
                                if ($w32tmOutput -match '([+-]?\d+\.\d+)s') {
                                    return [double]$matches[1]
                                }
                                return $null
                            ";
                        object? timeOffset = Shape(InvokeRemoteCommand(computerTarget, w32tmScript, new object?[] { dc }, Credential));

                        if (timeOffset is not null)
                        {
                            // Convert offset from seconds to minutes
                            timeDiff = Math.Abs(LanguagePrimitives.ConvertTo<double>(timeOffset) / 60);
                            WriteMessage(MessageLevel.Verbose, $"Successfully obtained time offset using w32tm: {PsString(timeOffset)} seconds");
                        }
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteMessage(MessageLevel.Verbose, $"w32tm method failed: {PsExceptionMessage(ex)}");
                    }

                    // Fall back to direct time query via Invoke-Command if w32tm failed
                    if (timeDiff is null)
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, "Falling back to Invoke-Command for DC time");
                            dcTime = Shape(InvokeRemoteCommand(dc, "Get-Date", null, Credential));

                            if (LanguagePrimitives.IsTrue(dcTime))
                            {
                                DateTime serverDt = LanguagePrimitives.ConvertTo<DateTime>(serverTimeValue);
                                DateTime dcDt = LanguagePrimitives.ConvertTo<DateTime>(dcTime);
                                timeDiff = Math.Abs((serverDt - dcDt).TotalMinutes);
                            }
                        }
                        catch (PipelineStoppedException)
                        {
                            throw;
                        }
                        catch (Exception ex)
                        {
                            WriteMessage(MessageLevel.Verbose, $"Invoke-Command method also failed: {PsExceptionMessage(ex)}");
                        }
                    }

                    string status;
                    string details;
                    string remediation;
                    // Only proceed if we successfully got a time difference
                    if (timeDiff is not null)
                    {
                        if (timeDiff > 5)
                        {
                            status = "Fail";
                            details = $"Time difference of {PsString(Math.Round(timeDiff.Value, 2))} minutes between server and DC exceeds threshold";
                            remediation = "Configure server to sync with domain controller. Use 'w32tm /config /syncfromflags:domhier /update'";
                        }
                        else
                        {
                            status = "Pass";
                            details = $"Server time synchronized with DC within {PsString(Math.Round(timeDiff.Value, 2))} minutes";
                            remediation = "None";
                        }
                    }
                    else
                    {
                        status = "Warning";
                        details = "Unable to query time difference from DC. Both w32tm and PSRemoting methods failed.";
                        remediation = "Verify domain connectivity. For w32tm: ensure Windows Time service is running. For PSRemoting: verify credentials have remote access.";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Time Synchronization (Server-DC)", "Time Sync", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Time Synchronization (Server-DC)", "Time Sync", "Warning",
                        $"Unable to compare time with DC: {PsExceptionMessage(ex)}",
                        "Verify domain connectivity and credentials"));
                }
                #endregion Time Synchronization Checks

                #region DNS Checks
                // Check 5: DNS forward lookup
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Testing DNS forward lookup");
                    string resolvedFqdn = System.Net.Dns.GetHostEntry(computerTarget!).HostName;
                    System.Net.IPAddress? resolvedIp = FirstOrNull(System.Net.Dns.GetHostAddresses(computerTarget!));

                    string status;
                    string details;
                    string remediation;
                    if (LanguagePrimitives.IsTrue(resolvedFqdn) && LanguagePrimitives.IsTrue(resolvedIp))
                    {
                        status = "Pass";
                        details = $"Forward lookup successful: {computerTarget} resolves to {resolvedIp!.ToString()}";
                        remediation = "None";
                    }
                    else
                    {
                        status = "Fail";
                        details = $"Forward lookup failed for {computerTarget}";
                        remediation = "Verify DNS A record exists for this server";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "DNS Forward Lookup", "DNS", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "DNS Forward Lookup", "DNS", "Fail",
                        $"DNS forward lookup failed: {PsExceptionMessage(ex)}",
                        "Verify DNS configuration and A record exists"));
                }

                // Check 6: DNS reverse lookup
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Testing DNS reverse lookup");
                    System.Net.IPAddress? ip = FirstOrNull(System.Net.Dns.GetHostAddresses(computerTarget!));
                    string reverseHost = System.Net.Dns.GetHostEntry(ip!.ToString()).HostName;

                    string status;
                    string details;
                    string remediation;
                    if (LanguagePrimitives.IsTrue(reverseHost))
                    {
                        status = "Pass";
                        details = $"Reverse lookup successful: {ip.ToString()} resolves to {reverseHost}";
                        remediation = "None";
                    }
                    else
                    {
                        status = "Warning";
                        details = $"Reverse lookup failed for {ip.ToString()}";
                        remediation = "Create PTR record in DNS for proper reverse lookup";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "DNS Reverse Lookup", "DNS", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "DNS Reverse Lookup", "DNS", "Warning",
                        $"DNS reverse lookup failed: {PsExceptionMessage(ex)}",
                        "Create PTR record in DNS for proper reverse lookup"));
                }
                #endregion DNS Checks

                #region Service Account Checks
                // Check 7: Verify service account
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Verifying SQL Server service account");
                        string serviceAccount = PsString(GetProperty(server, "ServiceAccount"));

                        string status;
                        string details;
                        string remediation;
                        if (PsLike(serviceAccount, "*\\*$"))
                        {
                            // gMSA or computer account (ends with $)
                            status = "Pass";
                            details = $"SQL Server running as managed service account or computer account: {serviceAccount} (supports Kerberos)";
                            remediation = "None";
                        }
                        else if (PsEquals(serviceAccount, "LocalSystem") || PsEquals(serviceAccount, "NetworkService"))
                        {
                            // LocalSystem or NetworkService - uses computer account for network auth
                            status = "Pass";
                            details = $"SQL Server running as {serviceAccount}. Uses computer account for Kerberos (works for single instance setups)";
                            remediation = "Consider using gMSA or dedicated domain service account for best practice, especially with multiple instances";
                        }
                        else if (PsLike(serviceAccount, "NT SERVICE\\*"))
                        {
                            // Virtual account - uses computer account for network auth
                            status = "Pass";
                            details = $"SQL Server running as virtual account {serviceAccount}. Uses computer account for Kerberos (works for single instance setups)";
                            remediation = "Consider using gMSA or dedicated domain service account for best practice, especially with multiple instances";
                        }
                        else if (Regex.IsMatch(serviceAccount, "^[^\\\\]+\\\\[^\\\\]+$", RegexOptions.IgnoreCase) && !PsLike(serviceAccount, "*\\*$"))
                        {
                            // Domain account (has backslash, no $ at end)
                            status = "Pass";
                            details = $"SQL Server running as domain service account: {serviceAccount} (supports Kerberos)";
                            remediation = "None";
                        }
                        else
                        {
                            // Local account or unrecognized format
                            status = "Fail";
                            details = $"SQL Server running as local account: {serviceAccount}. Kerberos requires domain-joined identity (gMSA, domain account, or computer account)";
                            remediation = "Change service account to gMSA (best practice), domain service account, or built-in account (LocalSystem/NetworkService/NT SERVICE)";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "Service Account Type", "Service Account", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "Service Account Type", "Service Account", "Warning",
                            $"Unable to verify service account: {PsExceptionMessage(ex)}",
                            "Manually verify SQL Server service account supports Kerberos (gMSA, domain account, or computer account)"));
                    }
                }

                // Check 8: Check account lock status
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Checking service account lock status");
                        string serviceAccount = PsString(GetProperty(server, "ServiceAccount"));

                        string status;
                        string details;
                        string remediation;
                        if (!PsLike(serviceAccount, "NT SERVICE\\*") && !PsEquals(serviceAccount, "LocalSystem") && !PsEquals(serviceAccount, "NetworkService"))
                        {
                            // Extract just the username from DOMAIN\username
                            string username = Regex.Replace(serviceAccount, "^.*\\\\", "", RegexOptions.IgnoreCase);

                            string objectCategory = username.EndsWith("$", StringComparison.Ordinal)
                                ? "msDS-GroupManagedServiceAccount"
                                : "User";

                            // Query AD for account status
                            using System.DirectoryServices.DirectorySearcher searcher = new();
                            searcher.Filter = $"(&(objectCategory={objectCategory})(samAccountName={username}))";
                            searcher.PropertiesToLoad.Add("lockoutTime");
                            searcher.PropertiesToLoad.Add("userAccountControl");
                            System.DirectoryServices.SearchResult? adUser = searcher.FindOne();

                            if (adUser is not null)
                            {
                                object lockoutTime = adUser.Properties["lockoutTime"][0];
                                object uac = adUser.Properties["userAccountControl"][0];
                                bool isDisabled = (LanguagePrimitives.ConvertTo<long>(uac) & 2) == 2;

                                if (LanguagePrimitives.ConvertTo<long>(lockoutTime) > 0)
                                {
                                    status = "Fail";
                                    details = $"Service account {serviceAccount} is locked out in Active Directory";
                                    remediation = "Unlock the account in Active Directory Users and Computers";
                                }
                                else if (isDisabled)
                                {
                                    status = "Fail";
                                    details = $"Service account {serviceAccount} is disabled in Active Directory";
                                    remediation = "Enable the account in Active Directory Users and Computers";
                                }
                                else
                                {
                                    status = "Pass";
                                    details = "Service account is not locked or disabled";
                                    remediation = "None";
                                }
                            }
                            else
                            {
                                status = "Warning";
                                details = "Unable to locate service account in Active Directory";
                                remediation = "Verify account exists and credentials have permission to query AD";
                            }
                        }
                        else
                        {
                            status = "Warning";
                            details = "Not using domain account, skipping lock check";
                            remediation = "None";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "Account Lock Status", "Service Account", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "Account Lock Status", "Service Account", "Warning",
                            $"Unable to check account status: {PsExceptionMessage(ex)}",
                            "Manually verify account is not locked in AD"));
                    }
                }

                // Check 9: Check "Account is sensitive and cannot be delegated"
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Checking delegation settings");
                        string serviceAccount = PsString(GetProperty(server, "ServiceAccount"));

                        string status;
                        string details;
                        string remediation;
                        if (!PsLike(serviceAccount, "NT SERVICE\\*") && !PsEquals(serviceAccount, "LocalSystem") && !PsEquals(serviceAccount, "NetworkService"))
                        {
                            // Extract just the username from DOMAIN\username
                            string username = Regex.Replace(serviceAccount, "^.*\\\\", "", RegexOptions.IgnoreCase);

                            string objectCategory = username.EndsWith("$", StringComparison.Ordinal)
                                ? "msDS-GroupManagedServiceAccount"
                                : "User";

                            // Query AD for account status
                            using System.DirectoryServices.DirectorySearcher searcher = new();
                            searcher.Filter = $"(&(objectCategory={objectCategory})(samAccountName={username}))";
                            searcher.PropertiesToLoad.Add("userAccountControl");
                            System.DirectoryServices.SearchResult? adUser = searcher.FindOne();

                            if (adUser is not null)
                            {
                                object uac = adUser.Properties["userAccountControl"][0];
                                bool notDelegated = (LanguagePrimitives.ConvertTo<long>(uac) & 1048576) == 1048576;

                                if (notDelegated)
                                {
                                    status = "Fail";
                                    details = "Account is marked as sensitive and cannot be delegated";
                                    remediation = "Remove 'Account is sensitive and cannot be delegated' flag in AD user properties";
                                }
                                else
                                {
                                    status = "Pass";
                                    details = "Account delegation is allowed";
                                    remediation = "None";
                                }
                            }
                            else
                            {
                                status = "Warning";
                                details = "Unable to query account delegation settings";
                                remediation = "Manually verify delegation settings in AD";
                            }
                        }
                        else
                        {
                            status = "Warning";
                            details = "Not using domain account, skipping delegation check";
                            remediation = "None";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "Delegation Settings", "Service Account", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "Delegation Settings", "Service Account", "Warning",
                            $"Unable to check delegation: {PsExceptionMessage(ex)}",
                            "Manually verify delegation settings in AD"));
                    }
                }
                #endregion Service Account Checks

                #region Authentication Validation
                // Check 10: Test-DbaConnectionAuthScheme
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Testing current authentication scheme");
                        Hashtable splatAuth = new Hashtable
                        {
                            { "SqlInstance", server },
                            { "EnableException", true }
                        };
                        object? authResult = Shape(NestedCommand.Invoke(this, "Test-DbaConnectionAuthScheme", splatAuth));
                        object? authScheme = GetProperty(authResult, "AuthScheme");

                        string status;
                        string details;
                        string remediation;
                        if (LanguagePrimitives.Equals(authScheme, "KERBEROS", ignoreCase: true))
                        {
                            status = "Pass";
                            details = "Currently using Kerberos authentication";
                            remediation = "None";
                        }
                        else if (LanguagePrimitives.Equals(authScheme, "NTLM", ignoreCase: true))
                        {
                            status = "Fail";
                            details = "Currently using NTLM authentication instead of Kerberos";
                            remediation = "Review failed checks above to identify why Kerberos is not working";
                        }
                        else
                        {
                            status = "Warning";
                            details = $"Authentication scheme: {PsString(authScheme)}";
                            remediation = "Verify authentication configuration";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "Current Authentication Scheme", "Authentication", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "Current Authentication Scheme", "Authentication", "Warning",
                            $"Unable to check auth scheme: {PsExceptionMessage(ex)}",
                            "Manually query sys.dm_exec_connections"));
                    }
                }
                #endregion Authentication Validation

                #region Network Connectivity Checks
                // Check 11: Test Kerberos ports (tcp/88, udp/88)
                EmitPortCheck(computerTarget, instanceName, 88, "Kerberos Port (TCP/88)",
                    "Testing Kerberos port connectivity",
                    failStatus: "Fail",
                    failRemediation: "Open TCP port 88 in firewall for Kerberos authentication",
                    catchRemediation: "Manually verify TCP/88 and UDP/88 connectivity to DC");

                // Check 12: Test LDAP ports (tcp/389, udp/389)
                EmitPortCheck(computerTarget, instanceName, 389, "LDAP Port (TCP/389)",
                    "Testing LDAP port connectivity",
                    failStatus: "Fail",
                    failRemediation: "Open TCP port 389 in firewall for LDAP queries",
                    catchRemediation: "Manually verify TCP/389 and UDP/389 connectivity to DC");

                // Check 13: Test Kerberos-Kdc port (tcp/464)
                EmitPortCheck(computerTarget, instanceName, 464, "Kerberos-Kdc Port (TCP/464)",
                    "Testing Kerberos password change port",
                    failStatus: "Warning",
                    failRemediation: "Open TCP port 464 for Kerberos password changes (optional)",
                    catchRemediation: "Manually verify TCP/464 connectivity to DC");
                #endregion Network Connectivity Checks

                #region Security Policy Checks
                // Check 14: Check encryption types
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Checking Kerberos encryption types");
                    string encryptionScript = @"
                            $regPath = ""HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters""
                            if (Test-Path $regPath) {
                                $encTypes = Get-ItemProperty -Path $regPath -Name ""SupportedEncryptionTypes"" -ErrorAction SilentlyContinue
                                return $encTypes.SupportedEncryptionTypes
                            } else {
                                return $null
                            }
                        ";
                    object? encryptionTypes = Shape(InvokeRemoteCommand(computerTarget, encryptionScript, null, Credential));

                    string status;
                    string details;
                    string remediation;
                    // RC4_HMAC_MD5 is 0x4, AES128 is 0x8, AES256 is 0x10
                    if (LanguagePrimitives.IsTrue(encryptionTypes))
                    {
                        long encValue = LanguagePrimitives.ConvertTo<long>(encryptionTypes);
                        bool hasRC4 = (encValue & 0x4) == 0x4;
                        if (hasRC4 || encValue == 0)
                        {
                            status = "Pass";
                            details = "RC4_HMAC_MD5 or default encryption types are enabled";
                            remediation = "None";
                        }
                        else
                        {
                            status = "Warning";
                            details = $"RC4_HMAC_MD5 not explicitly enabled. Current value: {PsString(encryptionTypes)}";
                            remediation = "Consider enabling RC4_HMAC_MD5 for compatibility if needed";
                        }
                    }
                    else
                    {
                        status = "Pass";
                        details = "Using default encryption types (not explicitly configured)";
                        remediation = "None";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Kerberos Encryption Types", "Security Policy", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Kerberos Encryption Types", "Security Policy", "Warning",
                        $"Unable to check encryption types: {PsExceptionMessage(ex)}",
                        "Manually verify encryption types in local security policy"));
                }

                // Check 15: Test-ComputerSecureChannel
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Testing computer secure channel");
                    object? secureChannelTest = Shape(InvokeRemoteCommand(computerTarget, "Test-ComputerSecureChannel", null, Credential));

                    string status;
                    string details;
                    string remediation;
                    if (LanguagePrimitives.IsTrue(secureChannelTest))
                    {
                        status = "Pass";
                        details = "Computer secure channel to domain is healthy";
                        remediation = "None";
                    }
                    else
                    {
                        status = "Fail";
                        details = "Computer secure channel to domain is broken";
                        remediation = "Run 'Test-ComputerSecureChannel -Repair' to reset computer account password";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Computer Secure Channel", "Security Policy", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Computer Secure Channel", "Security Policy", "Warning",
                        $"Unable to test secure channel: {PsExceptionMessage(ex)}",
                        "Manually run Test-ComputerSecureChannel"));
                }

                // Check 16: Check hosts file
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Checking hosts file for entries");
                    string hostsScript = @"
                            $hostsPath = ""$env:SystemRoot\System32\drivers\etc\hosts""
                            $hostsContent = Get-Content $hostsPath -ErrorAction SilentlyContinue
                            $nonCommentLines = $hostsContent | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' }
                            return $nonCommentLines
                        ";
                    object? hostsEntries = Shape(InvokeRemoteCommand(computerTarget, hostsScript, null, Credential));

                    string status;
                    string details;
                    string remediation;
                    if (LanguagePrimitives.IsTrue(hostsEntries))
                    {
                        status = "Warning";
                        details = $"Hosts file contains {PsCount(hostsEntries)} active entries that may override DNS";
                        remediation = "Review hosts file at C:\\Windows\\System32\\drivers\\etc\\hosts and remove unnecessary entries";
                    }
                    else
                    {
                        status = "Pass";
                        details = "No active entries in hosts file";
                        remediation = "None";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Hosts File", "Security Policy", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Hosts File", "Security Policy", "Warning",
                        $"Unable to check hosts file: {PsExceptionMessage(ex)}",
                        "Manually check C:\\Windows\\System32\\drivers\\etc\\hosts"));
                }
                #endregion Security Policy Checks

                #region SQL Server Configuration Checks
                // Check 17: Check SQL Server service account
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Validating SQL Server service account configuration");
                        string serviceAccount = PsString(GetProperty(server, "ServiceAccount"));

                        string status;
                        string details;
                        string remediation;
                        if (PsLike(serviceAccount, "*\\*$"))
                        {
                            // gMSA or computer account (ends with $)
                            if (PsLike(serviceAccount, "*gMSA*") || Regex.IsMatch(serviceAccount, "^\\w+\\\\\\w+\\$$", RegexOptions.IgnoreCase))
                            {
                                status = "Pass";
                                details = $"SQL Server using gMSA or managed service account: {serviceAccount} (best practice for Kerberos)";
                                remediation = "None";
                            }
                            else
                            {
                                status = "Pass";
                                details = $"SQL Server using computer account: {serviceAccount} (supports Kerberos)";
                                remediation = "None";
                            }
                        }
                        else if (PsEquals(serviceAccount, "LocalSystem") || PsEquals(serviceAccount, "NetworkService"))
                        {
                            // LocalSystem or NetworkService - uses computer account
                            status = "Pass";
                            details = $"SQL Server running as {serviceAccount} (uses computer account for Kerberos)";
                            remediation = "For best practice, consider gMSA or dedicated domain service account, especially in multi-instance or clustered environments";
                        }
                        else if (PsLike(serviceAccount, "NT SERVICE\\*"))
                        {
                            // Virtual account - uses computer account
                            status = "Pass";
                            details = $"SQL Server running as virtual account {serviceAccount} (uses computer account for Kerberos)";
                            remediation = "For best practice, consider gMSA or dedicated domain service account, especially in multi-instance or clustered environments";
                        }
                        else if (Regex.IsMatch(serviceAccount, "^[^\\\\]+\\\\[^\\\\]+$", RegexOptions.IgnoreCase) && !PsLike(serviceAccount, "*\\*$"))
                        {
                            // Domain account (has backslash, no $ at end)
                            status = "Pass";
                            details = $"SQL Server using domain service account: {serviceAccount} (supports Kerberos)";
                            remediation = "None";
                        }
                        else
                        {
                            // Local account or unrecognized format
                            status = "Fail";
                            details = $"SQL Server running as local account: {serviceAccount} (does not support Kerberos)";
                            remediation = "Change service account to gMSA (best practice), domain service account, or built-in account (LocalSystem/NetworkService/NT SERVICE) using SQL Server Configuration Manager";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "SQL Service Account Configuration", "SQL Configuration", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "SQL Service Account Configuration", "SQL Configuration", "Warning",
                            $"Unable to verify service account: {PsExceptionMessage(ex)}",
                            "Manually verify service account supports Kerberos in SQL Server Configuration Manager"));
                    }
                }

                // Check 18: Verify network protocols
                if (IsInstanceSet)
                {
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, "Checking SQL Server network protocol configuration");
                        // we need to use $server.SqlInstance to get the actual instance when the target is an Availability Group Listener
                        Hashtable splatNetConf = new Hashtable
                        {
                            { "SqlInstance", GetProperty(server, "SqlInstance") },
                            { "OutputType", "ServerProtocols" },
                            { "EnableException", true }
                        };
                        object? netConf = Shape(NestedCommand.Invoke(this, "Get-DbaNetworkConfiguration", splatNetConf));
                        object? tcpEnabled = GetProperty(netConf, "TcpIpEnabled");

                        string status;
                        string details;
                        string remediation;
                        if (LanguagePrimitives.IsTrue(tcpEnabled))
                        {
                            status = "Pass";
                            details = "TCP/IP protocol is enabled";
                            remediation = "None";
                        }
                        else
                        {
                            status = "Warning";
                            details = "TCP/IP protocol may not be enabled";
                            remediation = "Enable TCP/IP in SQL Server Configuration Manager for network connectivity";
                        }

                        WriteObject(BuildCheck(computerTarget, instanceName, "Network Protocol Configuration", "SQL Configuration", status, details, remediation));
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch (Exception ex)
                    {
                        WriteObject(BuildCheck(computerTarget, instanceName, "Network Protocol Configuration", "SQL Configuration", "Warning",
                            $"Unable to verify network protocols: {PsExceptionMessage(ex)}",
                            "Manually verify TCP/IP is enabled in SQL Server Configuration Manager"));
                    }
                }
                #endregion SQL Server Configuration Checks

                #region Client-Side Checks
                // Check 19: Run klist command
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Checking Kerberos ticket cache with klist");
                    Collection<PSObject> klistResult = InvokeCommand.InvokeScript(false, ScriptBlock.Create("& klist 2>&1 | Out-String"), null, null);
                    string klistOutput = klistResult.Count > 0 ? PsString(klistResult[0]) : string.Empty;

                    string status;
                    string details;
                    string remediation;
                    if (Regex.IsMatch(klistOutput, "Cached Tickets", RegexOptions.IgnoreCase))
                    {
                        if (Regex.IsMatch(klistOutput, "MSSQLSvc", RegexOptions.IgnoreCase))
                        {
                            status = "Pass";
                            details = "Kerberos tickets cached for SQL Server (MSSQLSvc)";
                            remediation = "None";
                        }
                        else
                        {
                            status = "Warning";
                            details = "No MSSQLSvc tickets in cache. May need fresh connection.";
                            remediation = "Close all SQL connections and reconnect to force new ticket acquisition";
                        }
                    }
                    else
                    {
                        status = "Warning";
                        details = "Unable to retrieve Kerberos ticket cache";
                        remediation = "Run 'klist' manually to inspect Kerberos tickets";
                    }

                    WriteObject(BuildCheck(computerTarget, instanceName, "Kerberos Ticket Cache", "Client", status, details, remediation));
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    WriteObject(BuildCheck(computerTarget, instanceName, "Kerberos Ticket Cache", "Client", "Warning",
                        $"Unable to run klist: {PsExceptionMessage(ex)}",
                        "Run 'klist' manually to inspect Kerberos tickets"));
                }
                #endregion Client-Side Checks
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction($"Error testing Kerberos for {target}", errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Error testing Kerberos for {target}", exception: ex, continueLoop: true);
                continue;
            }
        }
    }

    // Checks 11-13 share the exact Test-NetConnection shape; only port, check name, fail status
    // and remediation texts differ. The DC re-resolves per check like the PS source.
    private void EmitPortCheck(string? computerTarget, string? instanceName, int port, string checkName, string verboseText, string failStatus, string failRemediation, string catchRemediation)
    {
        try
        {
            WriteMessage(MessageLevel.Verbose, verboseText);
            System.DirectoryServices.ActiveDirectory.Domain domain = System.DirectoryServices.ActiveDirectory.Domain.GetCurrentDomain();
            string dc = domain.PdcRoleOwner.Name;

            using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
            shell.AddCommand("Test-NetConnection")
                .AddParameter("ComputerName", dc)
                .AddParameter("Port", port)
                .AddParameter("WarningAction", "SilentlyContinue");
            Collection<PSObject> results = shell.Invoke();
            object? tcpTest = results.Count > 0 ? results[0] : null;

            string status;
            string details;
            string remediation;
            if (LanguagePrimitives.IsTrue(GetProperty(tcpTest, "TcpTestSucceeded")))
            {
                status = "Pass";
                details = $"TCP port {port} accessible to DC {dc}";
                remediation = "None";
            }
            else
            {
                status = failStatus;
                details = $"TCP port {port} not accessible to DC {dc}";
                remediation = failRemediation;
            }

            WriteObject(BuildCheck(computerTarget, instanceName, checkName, "Network", status, details, remediation));
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            WriteObject(BuildCheck(computerTarget, instanceName, checkName, "Network", "Warning",
                $"Unable to test port connectivity: {PsExceptionMessage(ex)}",
                catchRemediation));
        }
    }

    // PS: Invoke-Command -ComputerName X -ScriptBlock {...} [-ArgumentList ...] [-Credential ...]
    // via the REAL engine cmdlet; a failure surfaces as the terminating error the enclosing
    // check catch expects (-ErrorAction is unbound, but the nested pipeline error is rethrown
    // to reproduce the PS statement-terminating shape inside the try).
    private Collection<PSObject> InvokeRemoteCommand(string? computerName, string scriptText, object?[]? argumentList, PSCredential? credential)
    {
        using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
        shell.AddCommand("Invoke-Command")
            .AddParameter("ComputerName", computerName)
            .AddParameter("ScriptBlock", ScriptBlock.Create(scriptText));
        if (argumentList is not null)
        {
            shell.AddParameter("ArgumentList", argumentList);
        }
        if (credential is not null)
        {
            shell.AddParameter("Credential", credential);
        }
        Collection<PSObject> output = shell.Invoke();
        if (shell.Streams.Error.Count > 0)
        {
            ErrorRecord record = shell.Streams.Error[0];
            throw new RuntimeException(record.Exception?.Message ?? "Invoke-Command failed", record.Exception, record);
        }
        return output;
    }

    // PS: $obj.Method(arg) through the adapter (the dbatools Query ScriptMethod on Smo.Server).
    private static object? InvokeMethod(object? source, string methodName, object? argument)
    {
        if (source is null)
        {
            throw new RuntimeException("You cannot call a method on a null-valued expression.");
        }
        PSMethodInfo? method = PSObject.AsPSObject(source).Methods[methodName];
        if (method is null)
        {
            string typeName = PSObject.AsPSObject(source).BaseObject?.GetType().FullName ?? "System.Object";
            throw new RuntimeException($"Method invocation failed because [{typeName}] does not contain a method named '{methodName}'.");
        }
        return method.Invoke(argument);
    }

    // PS: $result.ServerTime - a property read over whatever Query returned (DataRow scalar or
    // row collection member enumeration).
    private static object? GetMemberOfResult(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }
        object unwrapped = source is PSObject wrapped ? wrapped.BaseObject : source;
        if (unwrapped is not string && unwrapped is IEnumerable enumerable)
        {
            List<object?> values = new();
            foreach (object? item in enumerable)
            {
                if (item is null)
                {
                    continue;
                }
                PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
                if (property is not null)
                {
                    values.Add(property.Value);
                }
            }
            if (values.Count == 0)
            {
                return null;
            }
            if (values.Count == 1)
            {
                return values[0];
            }
            return values.ToArray();
        }
        return GetProperty(source, name);
    }

    // PS: $x | Where-Object Prop -eq $value (engine -eq semantics, case-insensitive strings),
    // returning the pipeline shape (null/scalar/array).
    private static object? WhereProperty(object? source, string propertyName, object? value)
    {
        List<object?> matches = new();
        foreach (object? item in EnumerateAny(source))
        {
            if (item is null)
            {
                continue;
            }
            object? candidate = PSObject.AsPSObject(item).Properties[propertyName]?.Value;
            if (LanguagePrimitives.Equals(candidate, value, ignoreCase: true))
            {
                matches.Add(item);
            }
        }
        if (matches.Count == 0)
        {
            return null;
        }
        if (matches.Count == 1)
        {
            return matches[0];
        }
        return matches.ToArray();
    }

    // PS: "$($x.Prop -join ', ')" - member enumeration joined with the literal separator.
    private static string JoinMemberValues(object? source, string propertyName, string separator)
    {
        List<string> parts = new();
        foreach (object? item in EnumerateAny(source))
        {
            if (item is null)
            {
                continue;
            }
            PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[propertyName];
            if (property is not null)
            {
                parts.Add(property.Value is null ? string.Empty : LanguagePrimitives.ConvertTo<string>(property.Value) ?? string.Empty);
            }
        }
        return string.Join(separator, parts);
    }

    private static PSObject BuildCheck(string? computerName, string? instanceName, string check, string category, string status, string details, string remediation)
    {
        PSObject obj = new();
        obj.Properties.Add(new PSNoteProperty("ComputerName", computerName));
        obj.Properties.Add(new PSNoteProperty("InstanceName", instanceName));
        obj.Properties.Add(new PSNoteProperty("Check", check));
        obj.Properties.Add(new PSNoteProperty("Category", category));
        obj.Properties.Add(new PSNoteProperty("Status", status));
        obj.Properties.Add(new PSNoteProperty("Details", details));
        obj.Properties.Add(new PSNoteProperty("Remediation", remediation));
        return obj;
    }

    // PS -like with the engine's wildcard semantics (case-insensitive).
    private static bool PsLike(string? value, string pattern)
    {
        WildcardPattern wildcard = new(pattern, WildcardOptions.IgnoreCase);
        return wildcard.IsMatch(value ?? string.Empty);
    }

    // PS -eq for strings (engine equality, case-insensitive).
    private static bool PsEquals(object? value, object? other)
    {
        return LanguagePrimitives.Equals(value, other, ignoreCase: true);
    }

    // PS "$value" string interpolation (engine conversion; null -> empty).
    private static string PsString(object? value)
    {
        if (value is null)
        {
            return string.Empty;
        }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    // PS "$($_.Exception.Message)"
    private static string PsExceptionMessage(Exception ex)
    {
        if (ex is RuntimeException rex && rex.ErrorRecord?.Exception is not null)
        {
            return rex.ErrorRecord.Exception.Message;
        }
        return ex.Message;
    }

    // PS .Count on a pipeline-shaped value: null -> 0, array -> length, scalar -> 1.
    private static int PsCount(object? value)
    {
        if (value is null)
        {
            return 0;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is object?[] many)
        {
            return many.Length;
        }
        return 1;
    }

    private static System.Net.IPAddress? FirstOrNull(System.Net.IPAddress[] addresses)
    {
        return addresses.Length > 0 ? addresses[0] : null;
    }

    private static object? GetProperty(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }
        return PSObject.AsPSObject(source).Properties[name]?.Value;
    }

    private static IEnumerable<object?> EnumerateAny(object? value)
    {
        if (value is null)
        {
            yield break;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is string)
        {
            yield return value;
            yield break;
        }
        if (unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable)
            {
                yield return item;
            }
            yield break;
        }
        yield return value;
    }

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? Shape(Collection<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++)
        {
            many[i] = output[i];
        }
        return many;
    }
}
