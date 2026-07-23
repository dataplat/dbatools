#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Database",
                "ExcludeDatabase",
                "Certificate",
                "ExcludeCertificate",
                "SharedPath",
                "MasterKeyPassword",
                "EncryptionPassword",
                "DecryptionPassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can copy a database certificate" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
            $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $backupPath -ItemType Directory

            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            # Create test databases
            $testDatabases = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Name dbatoolscopycred

            # Create master key and certificate on source
            $null = New-DbaDbMasterKey -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopycred -SecurePassword $securePassword
            $certificateName = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy1 -Name $certificateName -Database dbatoolscopycred

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $testDatabases | Remove-DbaDatabase -ErrorAction SilentlyContinue

            # Remove the backup directory.
            Remove-Item -Path $backupPath -Recurse

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Successfully copies a certificate" {
            $splatCopyCert = @{
                Source             = $TestConfig.InstanceCopy1
                Destination        = $TestConfig.InstanceCopy2
                EncryptionPassword = $securePassword
                MasterKeyPassword  = $securePassword
                Database           = "dbatoolscopycred"
                SharedPath         = $backupPath
            }
            $results = Copy-DbaDbCertificate @splatCopyCert

            $results.Notes | Should -BeNullOrEmpty
            $results.Status | Should -Be "Successful"

            $sourceDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database dbatoolscopycred
            $destDb = Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred

            $results.SourceDatabaseID | Should -Be $sourceDb.ID
            $results.DestinationDatabaseID | Should -Be $destDb.ID

            Get-DbaDbCertificate -SqlInstance $TestConfig.InstanceCopy2 -Database dbatoolscopycred -Certificate $certificateName | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "$CommandName streaming across destinations" -Tag IntegrationTests {
    # The command loops over -Destination, emitting a status row per certificate per destination,
    # and a destination that cannot be connected raises a terminating Stop-Function once
    # -EnableException is set. Output that a buffered scope holds until the loop returns is lost
    # when that throw happens; streamed output is not. The live copy above uses a single
    # destination, so it cannot observe the difference - this leg drives an emit-then-throw batch.
    # Fully mocked: no instance is contacted and nothing is written, so it needs no copy fixture.
    Context "When a later destination cannot be reached under -EnableException" {
        BeforeAll {
            # A server's Databases collection is both enumerable and addressable by database name,
            # and the command uses it both ways in the same pass, so the stand-in has to be too.
            if (-not ("DbaTestKeyedDatabaseCollection" -as [type])) {
                Add-Type -TypeDefinition @"
using System.Collections;
using System.Collections.Generic;
public class DbaTestKeyedDatabaseCollection : IEnumerable
{
    private readonly List<object> items = new List<object>();
    private readonly Dictionary<string, object> byName = new Dictionary<string, object>();
    public void Add(string name, object item) { items.Add(item); byName[name] = item; }
    public object this[string name] { get { object found; return byName.TryGetValue(name, out found) ? found : null; } }
    public IEnumerator GetEnumerator() { return items.GetEnumerator(); }
}
"@
            }

            # Source-side objects the begin block gathers. The certificate is encrypted by master
            # key because the command only walks its certificate loop for that encryption type.
            $sourceServerStub = [PSCustomObject]@{
                Name           = "certstreamsrc"
                ServiceAccount = "NT Service\MSSQLSERVER"
            }
            $sourceDbStub = [PSCustomObject]@{
                Name   = "certstreamdb"
                ID     = 11
                Parent = $sourceServerStub
            }
            $sourceCertStub = [PSCustomObject]@{
                Name                     = "certstreamcert"
                PrivateKeyEncryptionType = "MasterKey"
                Parent                   = $sourceDbStub
            }

            # The reachable destination already holds the certificate, so the command emits its
            # "already exists" status row without a backup/restore round trip.
            $destDbStub = [PSCustomObject]@{
                Name         = "certstreamdb"
                ID           = 22
                Certificates = @([PSCustomObject]@{ Name = "certstreamcert" })
            }
            $destDbStub | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }
            $destMasterStub = [PSCustomObject]@{ Name = "master"; ID = 1 }
            $destMasterStub | Add-Member -MemberType ScriptMethod -Name Refresh -Value { }

            $destDatabases = New-Object -TypeName DbaTestKeyedDatabaseCollection
            $destDatabases.Add("master", $destMasterStub)
            $destDatabases.Add("certstreamdb", $destDbStub)

            $destServerStub = [PSCustomObject]@{
                Name           = "certstreamdest"
                ComputerName   = "certstreamdest"
                ServiceAccount = "NT Service\MSSQLSERVER"
                Databases      = $destDatabases
            }
            # Test-DbaPath types its instance parameter, so the stand-in has to convert like a server.
            $destServerStub.PSObject.TypeNames.Insert(0, "Microsoft.SqlServer.Management.Smo.Server")
            $destDbStub | Add-Member -MemberType NoteProperty -Name Parent -Value $destServerStub

            Mock Get-DbaDbCertificate -ModuleName dbatools -MockWith { $sourceCertStub }
            Mock Test-DbaPath -ModuleName dbatools -MockWith { $true }
            # A master key is present everywhere the command looks, so neither the "skipped" note
            # nor the auto-creation branch fires and the run reaches the per-certificate emit.
            Mock Get-DbaDbMasterKey -ModuleName dbatools -MockWith { [PSCustomObject]@{ Name = "##MS_DatabaseMasterKey##" } }

            # The second destination fails to connect, which is the source's own terminating path
            # once -EnableException is set. Nothing here reaches a network stack.
            Mock Connect-DbaInstance -ModuleName dbatools -MockWith {
                param($SqlInstance)
                if ("$SqlInstance" -eq "certstreamdest") {
                    $destServerStub
                } else {
                    throw "The destination could not be reached"
                }
            }

            $emitted = @()
            $threw = $false
            try {
                $splatCopyThenThrow = @{
                    Source          = "certstreamsrc"
                    Destination     = "certstreamdest", "certstreamgone"
                    SharedPath      = $TestConfig.Temp
                    EnableException = $true
                    Confirm         = $false
                }
                Copy-DbaDbCertificate @splatCopyThenThrow | ForEach-Object { $emitted += $PSItem }
            } catch {
                $threw = $true
            }
        }

        It "Throws when a later destination cannot be reached" {
            $threw | Should -BeTrue
        }

        It "Preserves the row emitted for the earlier destination (streaming, not buffered)" {
            @($emitted).Count | Should -Be 1
            @($emitted)[0].Name | Should -Be "certstreamcert"
            @($emitted)[0].DestinationServer | Should -Be "certstreamdest"
        }
    }
}