#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbServiceBrokerService",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- Service Broker is not supported in Azure SQL Database (Microsoft Learn, features comparison: Azure SQL Managed Instance only), and SMO's BrokerService enumerator declares no cloud support.

Describe "Native Service Broker service behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeBrokerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeBrokerDatabaseName = "native_broker_service_" + [Guid]::NewGuid().ToString("N")
        $nativeBrokerDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeBrokerServer, $nativeBrokerDatabaseName
        $nativeBrokerDatabase.Create()
        $nativeBrokerServiceName = "native_service"
        $nativeBrokerQueueName = "native_queue"
        $nativeBrokerDatabase.ExecuteNonQuery("CREATE QUEUE [dbo].[$nativeBrokerQueueName];")
        $nativeBrokerDatabase.ExecuteNonQuery("CREATE SERVICE [$nativeBrokerServiceName] ON QUEUE [dbo].[$nativeBrokerQueueName] ([DEFAULT]);")
        $nativeBrokerDisplay = "ComputerName,InstanceName,SqlInstance,Database,Owner,ServiceID,Name,QueueSchema,QueueName"
    }

    AfterAll {
        if ($nativeBrokerServer -and $nativeBrokerDatabaseName) {
            $nativeBrokerServer.Databases.Refresh()
            if ($nativeBrokerServer.Databases[$nativeBrokerDatabaseName]) {
                $splatRemoveNativeBrokerDatabase = @{
                    SqlInstance     = $nativeBrokerServer
                    Database        = $nativeBrokerDatabaseName
                    Confirm         = $false
                    EnableException = $true
                }
                Remove-DbaDatabase @splatRemoveNativeBrokerDatabase
            }
        }
    }

    It "preserves typed services, metadata and the ServiceID display alias across pipeline records" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeBrokerRead = @{
            Database             = $nativeBrokerDatabaseName
            ExcludeSystemService = $true
            EnableException      = $true
        }
        $nativeBrokerRows = @(@($nativeBrokerServer, $nativeBrokerServer) | Get-DbaDbServiceBrokerService @splatNativeBrokerRead)
        $nativeBrokerRows.Count | Should -Be 2
        foreach ($nativeBrokerRow in $nativeBrokerRows) {
            $nativeBrokerRow | Should -BeOfType Microsoft.SqlServer.Management.Smo.Broker.BrokerService
            $nativeBrokerRow.Name | Should -BeExactly $nativeBrokerServiceName
            $nativeBrokerRow.Database | Should -BeExactly $nativeBrokerDatabaseName
            $nativeBrokerRow.ComputerName | Should -BeExactly $nativeBrokerServer.ComputerName
            $nativeBrokerRow.InstanceName | Should -BeExactly $nativeBrokerServer.ServiceName
            $nativeBrokerRow.SqlInstance | Should -BeExactly $nativeBrokerServer.DomainInstanceName
            $nativeBrokerRow.ServiceID | Should -Be $nativeBrokerRow.ID
            $nativeBrokerRow.PSObject.Properties["ServiceID"].MemberType.ToString() | Should -BeExactly "AliasProperty"
            ($nativeBrokerRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeBrokerDisplay
            @($nativeBrokerRow.PSObject.Properties | Where-Object Name -eq "SqlInstance").Count | Should -Be 1
        }
    }

    It "matches database names literally and case-insensitively with exclusion taking precedence" {
        $splatNativeBrokerFilter = @{
            SqlInstance          = $nativeBrokerServer
            Database             = $nativeBrokerDatabaseName.ToUpperInvariant()
            ExcludeSystemService = $true
            EnableException      = $true
        }
        $nativeBrokerIncluded = @(Get-DbaDbServiceBrokerService @splatNativeBrokerFilter)
        $nativeBrokerIncluded.Count | Should -Be 1
        $nativeBrokerIncluded[0].Database | Should -BeExactly $nativeBrokerDatabaseName
        $splatNativeBrokerFilter.ExcludeDatabase = $nativeBrokerDatabaseName.ToUpperInvariant()
        @(Get-DbaDbServiceBrokerService @splatNativeBrokerFilter).Count | Should -Be 0
        $splatNativeBrokerFilter.Remove("ExcludeDatabase")
        $splatNativeBrokerFilter.Database = "native_broker_service_*"
        @(Get-DbaDbServiceBrokerService @splatNativeBrokerFilter).Count | Should -Be 0
    }

    It "includes system services by default and when -ExcludeSystemService is explicitly false" -Tag "NativeChecklist:switch-false" {
        # Pinned public/Get-DbaDbServiceBrokerService.ps1:120 uses Test-Bound, so an explicit false
        # switch still excluded system services (dead parameter value). Explicit false is now absent.
        $splatNativeBrokerBound = @{
            SqlInstance     = $nativeBrokerServer
            Database        = $nativeBrokerDatabaseName
            EnableException = $true
        }
        $nativeBrokerAll = @(Get-DbaDbServiceBrokerService @splatNativeBrokerBound)
        @($nativeBrokerAll | Where-Object IsSystemObject).Count | Should -BeGreaterThan 0
        $splatNativeBrokerBound.ExcludeSystemService = $false
        $nativeBrokerExplicitFalse = @(Get-DbaDbServiceBrokerService @splatNativeBrokerBound)
        $nativeBrokerExplicitFalse.Count | Should -Be $nativeBrokerAll.Count
        @($nativeBrokerExplicitFalse | Where-Object IsSystemObject).Count | Should -Be @($nativeBrokerAll | Where-Object IsSystemObject).Count
        @($nativeBrokerExplicitFalse | Where-Object Name -eq $nativeBrokerServiceName).Count | Should -Be 1
        $splatNativeBrokerBound.ExcludeSystemService = $true
        $nativeBrokerFiltered = @(Get-DbaDbServiceBrokerService @splatNativeBrokerBound)
        $nativeBrokerFiltered.Count | Should -Be 1
        $nativeBrokerFiltered[0].Name | Should -BeExactly $nativeBrokerServiceName
        @($nativeBrokerFiltered | Where-Object IsSystemObject).Count | Should -Be 0
    }

    It "warns and continues after a failed instance without forwarding EnableException to database discovery" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
        $nativeBrokerSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeBrokerListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeBrokerListener.Start()
            $nativeBrokerFailedInstance = "127.0.0.1," + $nativeBrokerListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            foreach ($nativeBrokerEnableException in $false, $true) {
                $nativeBrokerWarnings = @()
                $splatNativeBrokerFailure = @{
                    Database             = $nativeBrokerDatabaseName
                    ExcludeSystemService = $true
                    EnableException      = $nativeBrokerEnableException
                    WarningAction        = "SilentlyContinue"
                    WarningVariable      = "nativeBrokerWarnings"
                }
                $nativeBrokerContinued = @(
                    @($nativeBrokerServer, $nativeBrokerFailedInstance, $nativeBrokerServer) |
                        Get-DbaDbServiceBrokerService @splatNativeBrokerFailure
                )
                $nativeBrokerContinued.Count | Should -Be 2
                @($nativeBrokerContinued | Where-Object Name -ne $nativeBrokerServiceName).Count | Should -Be 0
                ($nativeBrokerWarnings -join " ") | Should -BeLike "*Failure*"
            }
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeBrokerSavedTimeout
            $nativeBrokerListener.Stop()
        }
    }

    # NativeChecklist: whatif-confirm N/A -- read-only command; no SupportsShouldProcess or WhatIf/Confirm parameters.

    It "does not write the empty-service message for a new database whose system services exist" {
        # Pinned public/Get-DbaDbServiceBrokerService.ps1:114-115 checks Count -eq 0 before any filter;
        # every new database already contains system services.
        $nativeBrokerEmptyText = "No Service Broker Services exist in the [$nativeBrokerDatabaseName] database on"
        $nativeBrokerEmptyBefore = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($nativeBrokerEmptyText) }).Count
        $splatNativeBrokerMessage = @{
            SqlInstance     = $nativeBrokerServer
            Database        = $nativeBrokerDatabaseName
            EnableException = $true
            Verbose         = $true
        }
        $nativeBrokerMessageRecords = @(Get-DbaDbServiceBrokerService @splatNativeBrokerMessage 4>&1)
        @($nativeBrokerMessageRecords | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No Service Broker Services exist*" }).Count | Should -Be 0
        @($nativeBrokerMessageRecords | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] -and $PSItem.IsSystemObject }).Count | Should -BeGreaterThan 0
        @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $PSItem.Message -and $PSItem.Message.StartsWith($nativeBrokerEmptyText) }).Count | Should -Be $nativeBrokerEmptyBefore
    }

    Context "Connection callback failures" {
        BeforeAll {
            $gatherProbeMessage = "native gather callback probe " + [Guid]::NewGuid().ToString("N")
            $gatherProbeAssembly = (Get-Command -Name "Get-DbaDbServiceBrokerService" -CommandType Cmdlet).ImplementingType.Assembly
            $gatherProbeSelection = $gatherProbeAssembly.GetType("Dataplat.Dbatools.Commands.NativeDatabaseSelection", $true)
            $gatherProbeMethod = $gatherProbeSelection.GetMethod("Gather", [System.Reflection.BindingFlags]"Static, NonPublic")
            if ($null -eq $gatherProbeMethod) {
                throw "The callback fixture requires NativeDatabaseSelection.Gather"
            }
            if (-not ([System.Management.Automation.PSTypeName]"NativeDatabaseSelectionTests.InvokeNativeGatherCallbackProbe").Type) {
                $gatherProbeSource = @"
using System;
using System.Management.Automation;
using System.Reflection;
using System.Runtime.ExceptionServices;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Parameter;
namespace NativeDatabaseSelectionTests {
    [Cmdlet(VerbsLifecycle.Invoke, "NativeGatherCallbackProbe")]
    public sealed class InvokeNativeGatherCallbackProbe : DbaBaseCmdlet {
        [Parameter(Mandatory = true)]
        public DbaInstanceParameter[] SqlInstance { get; set; }
        [Parameter(Mandatory = true)]
        public MethodInfo Gather { get; set; }
        [Parameter(Mandatory = true)]
        public string FailureMessage { get; set; }
        public void Fail(object server) { throw new InvalidOperationException(FailureMessage); }
        protected override void ProcessRecord() {
            ParameterInfo[] parameters = Gather.GetParameters();
            Delegate connected = Delegate.CreateDelegate(parameters[5].ParameterType, this, GetType().GetMethod("Fail"));
            Func<bool> interrupted = delegate { return false; };
            object result;
            try {
                result = Gather.Invoke(null, new object[] { this, SqlInstance, null, null, null, connected, interrupted });
            } catch (TargetInvocationException e) {
                ExceptionDispatchInfo.Capture(e.InnerException).Throw();
                throw;
            }
            WriteObject(result, true);
        }
    }
}
"@
                $splatGatherProbeType = @{
                    TypeDefinition       = $gatherProbeSource
                    ReferencedAssemblies = @(
                        [Dataplat.Dbatools.Commands.DbaBaseCmdlet].Assembly.Location
                        [Microsoft.Data.SqlClient.SqlCommand].Assembly.Location
                        [Microsoft.SqlServer.Management.Common.ServerConnection].Assembly.Location
                        [psobject].Assembly.Location
                    )
                    IgnoreWarnings       = $true
                }
                Add-Type @splatGatherProbeType
            }
            Import-Module -Assembly ([System.Management.Automation.PSTypeName]"NativeDatabaseSelectionTests.InvokeNativeGatherCallbackProbe").Type.Assembly
        }

        It "surfaces a failing connection callback instead of reporting a connection failure" {
            # Upstream connects inside Get-DbaDatabase and has no caller callback, so only the
            # connection attempt itself may produce the "Failure" ConnectionError warning.
            $gatherProbeWarnings = @()
            $gatherProbePreviousErrors = @($global:Error)
            $gatherProbeCaught = $null
            $splatGatherProbe = @{
                SqlInstance     = $nativeBrokerServer
                Gather          = $gatherProbeMethod
                FailureMessage  = $gatherProbeMessage
                WarningAction   = "SilentlyContinue"
                WarningVariable = "gatherProbeWarnings"
            }
            try {
                $null = Invoke-NativeGatherCallbackProbe @splatGatherProbe
            } catch {
                $gatherProbeCaught = $PSItem
            }
            $gatherProbeCaught | Should -Not -BeNullOrEmpty
            $gatherProbeException = $gatherProbeCaught.Exception
            while ($null -ne $gatherProbeException -and $gatherProbeException -isnot [System.InvalidOperationException]) {
                $gatherProbeException = $gatherProbeException.InnerException
            }
            $gatherProbeException.Message | Should -BeExactly $gatherProbeMessage
            ($gatherProbeWarnings -join " ") | Should -Not -BeLike "*Failure*"
            $gatherProbeHelperErrors = @($global:Error | Where-Object {
                    $gatherProbePreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*"
                })
            $gatherProbeHelperErrors.Count | Should -Be 0
        }
    }
}

Describe "Native Get-DbaDbServiceBrokerService over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_service_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE QUEUE [dbo].[native_login_queue];")
            $loginDatabase.ExecuteNonQuery("CREATE SERVICE [native_login_service] ON QUEUE [dbo].[native_login_queue] ([DEFAULT]);")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginService = @{
                SqlInstance          = $loginInstance
                SqlCredential        = $loginCred
                Database             = $loginDbName
                ExcludeSystemService = $true
                EnableException      = $true
            }
            $loginRows = @(Get-DbaDbServiceBrokerService @splatLoginService)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_service"
            $loginRows[0].QueueName | Should -BeExactly "native_login_queue"
        }

        It "fails cleanly without the credential: a warning and no output with either EnableException value" {
            # As upstream, the connection failure belongs to the nested database gather, which is not given
            # -EnableException, so it warns and continues in both cases.
            foreach ($loginEnableException in $false, $true) {
                $loginWarnings = @()
                $splatLoginNoCredential = @{
                    SqlInstance     = $loginInstance
                    Database        = $loginDbName
                    EnableException = $loginEnableException
                    WarningAction   = "SilentlyContinue"
                    WarningVariable = "loginWarnings"
                }
                $loginResult = @(Get-DbaDbServiceBrokerService @splatLoginNoCredential)
                $loginResult.Count | Should -Be 0
                ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            }
        }
    }
}
