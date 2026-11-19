#nullable enable

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates SQL Server client aliases in the Windows registry (HKLM ConnectTo keys, both
/// hives on 64-bit). Port of public/New-DbaClientAlias.ps1 (W1-026). The registry
/// scriptblock rides Invoke-Command2 VERBATIM (local in-process or remoting, exactly like
/// the function), and Test-ElevationRequirement runs module-scoped with -Continue: the
/// private helper's dynamically scoped continue propagates out of the nested script as the
/// engine flow-control exception and continues THIS cmdlet's computer loop (the W1-025
/// CallerFlow discovery, inverted — here the cmdlet is the catcher). Its [bool]
/// $EnableException = $EnableException dynamic-scope default is passed explicitly because
/// the module scope chain cannot see this cmdlet's value. Warnings from both helpers merge
/// back 3&gt;&amp;1 for caller -WarningVariable parity. Under -WhatIf the write is skipped
/// but the Get-DbaClientAlias read-back still runs, like the function. PS function
/// parameters are positional by default, so Positions 0-4 are pinned.
/// Surface pinned by migration/baselines/New-DbaClientAlias.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaClientAlias", SupportsShouldProcess = true)]
public sealed class NewDbaClientAliasCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 2)]
    public DbaInstanceParameter? ServerName { get; set; }

    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Alias { get; set; } = null!;

    [Parameter(Position = 4)]
    [PsStringCast]
    [ValidateSet("TCPIP", "NamedPipes")]
    public string Protocol { get; set; } = "TCPIP";

    protected override void BeginProcessing()
    {
        // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME (bind-time cast;
        // a null environment value casts to null and the process loop just never runs).
        if (!TestBound("ComputerName"))
        {
            string? localName = Environment.GetEnvironmentVariable("COMPUTERNAME");
            if (localName is not null)
                ComputerName = (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(localName, typeof(DbaInstanceParameter[]), CultureInfo.InvariantCulture);
        }
    }

    protected override void ProcessRecord()
    {
        string serverstring;
        if (PsString.Eq(Protocol, "TCPIP"))
            serverstring = "DBMSSOCN," + PsText(ServerName);
        else
            serverstring = "DBNMPNTW,\\\\" + PsText(ServerName) + "\\pipe\\sql\\query";

        if (ComputerName is null)
            return;

        // PS: foreach ($computer in $ComputerName.ComputerName) - member enumeration.
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            string computerText = computer.ComputerName;

            // PS: $null = Test-ElevationRequirement -ComputerName $computer -Continue -
            // output discarded, warnings bubble, the failure continue targets this loop.
            try
            {
                NestedCommand.InvokeScoped(this, TestElevationScript, computerText, EnableException.ToBool());
            }
            catch (FlowControlException)
            {
                continue;
            }

            if (ShouldProcess(computerText, "Adding " + Alias))
            {
                try
                {
                    foreach (PSObject item in NestedCommand.InvokeScoped(this, InvokeCommand2Script, computerText, Credential, ServerName, Alias, serverstring))
                        WriteObject(item);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure", target: computerText, errorRecord: ToCaughtRecord(ex), continueLoop: true);
                    continue;
                }
            }

            // PS: Get-DbaClientAlias -ComputerName $computer -Credential $Credential |
            //     Where-Object AliasName -eq $Alias (runs under -WhatIf too)
            Hashtable getParams = new();
            getParams["ComputerName"] = computerText;
            getParams["Credential"] = Credential;
            foreach (PSObject aliasItem in NestedCommand.Invoke(this, "Get-DbaClientAlias", getParams))
            {
                if (PsOps.Eq(PsProperty.Get(aliasItem, "AliasName"), Alias))
                    WriteObject(aliasItem);
            }
        }
    }

    /// <summary>PS string interpolation of a value ("$ServerName").</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>PS: catch { $_ } - a nested terminating error carries the original failing
    /// record; a hand-built RuntimeException's lazy record drops the inner chain
    /// (ParentContainsErrorRecordException), so that shape rebuilds from the exception.</summary>
    private static ErrorRecord ToCaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null &&
            runtime.ErrorRecord.Exception is not ParentContainsErrorRecordException)
        {
            return runtime.ErrorRecord;
        }
        return new ErrorRecord(ex, "New-DbaClientAlias", ErrorCategory.NotSpecified, null);
    }

    private const string TestElevationScript = """
param($computer, $enable)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $enable)
    Test-ElevationRequirement -ComputerName $computer -Continue -EnableException $enable 3>&1
} $computer $enable
""";

    // The inner registry scriptblock is VERBATIM from the function's begin block (comments
    // included) - Invoke-Command2 runs it in-process locally or serializes it for remoting.
    private const string InvokeCommand2Script = """
param($computer, $credential, $ServerName, $Alias, $serverstring)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($computer, $credential, $ServerName, $Alias, $serverstring)
    # This is a script block so cannot use messaging system
    $scriptBlock = {
        $basekeys = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\MSSQLServer", "HKLM:\SOFTWARE\Microsoft\MSSQLServer"
        #Variable marked as unused by PSScriptAnalyzer
        #$ServerName = $args[0]
        $Alias = $args[1]
        $serverstring = $args[2]

        if ($env:PROCESSOR_ARCHITECTURE -like "*64*") { $64bit = $true }

        foreach ($basekey in $basekeys) {
            if ($64bit -ne $true -and $basekey -like "*WOW64*") { continue }

            $client = "$basekey\Client"

            if ((Test-Path $client) -eq $false) {
                # "Creating $client key"
                $null = New-Item -Path $client -Force
            }

            $connect = "$client\ConnectTo"

            if ((Test-Path $connect) -eq $false) {
                # "Creating $connect key"
                $null = New-Item -Path $connect -Force
            }

            <#
            #Variable marked as unused by PSScriptAnalyzer
            #Looks like it was once used for a Verbose Message
            if ($basekey -like "*WOW64*") {
                $architecture = "32-bit"
            } else {
                $architecture = "64-bit"
            }
            #>
            <# DO NOT use Write-Message as this is inside of a script block #>
            # Write-Verbose "Creating/updating alias for $ComputerName for $architecture"
            $null = New-ItemProperty -Path $connect -Name $Alias -Value $serverstring -PropertyType String -Force
        }
    }
    Invoke-Command2 -ComputerName $computer -Credential $credential -ScriptBlock $scriptBlock -ErrorAction Stop -ArgumentList $ServerName, $Alias, $serverstring 3>&1
} $computer $credential $ServerName $Alias $serverstring
""";
}
