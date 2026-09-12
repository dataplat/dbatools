#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Invoke-DbaDbDecryptObject",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        # These tests call private functions, which are only reachable inside the module. Get-Module
        # returns one object for every loaded copy of dbatools, and a session readily holds more than
        # one: Invoke-ManualPester imports dbatools.psd1 and dbatools.psm1, which leaves a binary module
        # and a script module both named dbatools. Handing that array to the call operator makes
        # PowerShell join the names and look for a command called "dbatools dbatools", and the call
        # operator refuses a binary module outright, so the script copy that actually carries the
        # private functions is resolved once here and reused.
        $dbatoolsModule = $null
        foreach ($candidate in @(Get-Module dbatools | Where-Object ModuleType -eq "Script")) {
            $hasPrivateFunction = $false
            try {
                $hasPrivateFunction = & $candidate { [bool](Get-Command ConvertFrom-DbccPageDump -ErrorAction SilentlyContinue) }
            } catch {
                $hasPrivateFunction = $false
            }
            if ($hasPrivateFunction) {
                $dbatoolsModule = $candidate
                break
            }
        }
        if ($null -eq $dbatoolsModule) {
            throw "No loaded dbatools script module exposes the private functions these tests call. Import dbatools.psm1 before running them."
        }
    }

    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Database",
                "EnableException",
                "EncodingType",
                "ExportDestination",
                "ObjectName",
                "SqlCredential",
                "SqlInstance",
                "DataPages"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Page dump parsing" {
        BeforeDiscovery {
            # DBCC PAGE does not use one fixed line width, and the ASCII gutter at the end of a line can
            # begin with a token of exactly eight hex digits, which the rule "eight hex digits is data"
            # would take as four more bytes of the page.
            $dumpCase = @(
                @{
                    LineWidth = 16
                    HexGutter = $false
                    Label     = "16 bytes per line"
                },
                @{
                    LineWidth = 20
                    HexGutter = $false
                    Label     = "20 bytes per line"
                },
                @{
                    LineWidth = 16
                    HexGutter = $true
                    Label     = "16 bytes per line and a gutter that starts with hex digits"
                },
                @{
                    LineWidth = 20
                    HexGutter = $true
                    Label     = "20 bytes per line and a gutter that starts with hex digits"
                }
            )
        }

        BeforeAll {
            # A deterministic page, so that a failure is reproducible.
            $expectedPage = New-Object byte[] 8192
            for ($pageOffset = 0; $pageOffset -lt 8192; $pageOffset++) {
                $expectedPage[$pageOffset] = [byte](($pageOffset * 37 + 11) % 256)
            }

            function Format-TestPageDump {
                param(
                    [byte[]]$Page,
                    [int]$LineWidth,
                    [switch]$HexGutter
                )

                # The address DBCC prints is a memory address, so it does not start at zero.
                $baseAddress = [Convert]::ToUInt64("0000000332FF4000", 16)
                $dumpLine = @()

                for ($offset = 0; $offset -lt $Page.Length; $offset += $LineWidth) {
                    $take = [Math]::Min($LineWidth, $Page.Length - $offset)
                    $hex = ""
                    for ($group = 0; $group -lt $take; $group += 4) {
                        $token = ""
                        for ($byteIndex = 0; $byteIndex -lt 4 -and ($group + $byteIndex) -lt $take; $byteIndex++) {
                            $token += $Page[$offset + $group + $byteIndex].ToString("x2")
                        }
                        $hex += "$token "
                    }

                    # A real gutter renders the page bytes as characters, so a space byte splits it into
                    # tokens and a run of hex digit characters makes the first token look like page data.
                    if ($HexGutter) {
                        $gutter = "deadbeef ......."
                    } else {
                        $gutter = "................"
                    }

                    $dumpLine += "$(($baseAddress + $offset).ToString("X16")):   $hex $gutter"
                }

                return $dumpLine
            }
        }

        It "Parses a page dump with <Label>" -ForEach $dumpCase {
            $dumpLine = Format-TestPageDump -Page $expectedPage -LineWidth $LineWidth -HexGutter:$HexGutter
            $actualPage = & $dbatoolsModule { param($line) ConvertFrom-DbccPageDump -DumpLine $line } $dumpLine
            $actualPage.Length | Should -Be 8192
            Compare-Object -ReferenceObject $expectedPage -DifferenceObject $actualPage -SyncWindow 0 | Should -BeNullOrEmpty
        }

        It "Fails instead of returning a page with a hole in it when a line is missing" {
            $dumpLine = @(Format-TestPageDump -Page $expectedPage -LineWidth 20)
            $missingLine = @($dumpLine[0..9]) + @($dumpLine[11..($dumpLine.Count - 1)])
            { & $dbatoolsModule { param($line) ConvertFrom-DbccPageDump -DumpLine $line } $missingLine } | Should -Throw -ExpectedMessage "*Incomplete page dump*"
        }
    }

    Context "Multi chunk definitions" {
        BeforeAll {
            # A definition can span several sys.sysobjvalues rows, one per subobjid, but SQL Server appears
            # never to do it - it uses one row and lets the off row machinery deal with size. So no fixture
            # can create a multi chunk definition, and these unit tests are the only cover this path has.
            $chunkFamilyGuid = [guid]"7e11756e-abe9-11d2-896a-00c04fd9374a"
            $chunkObjectId = 1253579504

            # Builds the ciphertext of a chunk the way SQL Server stores it, so the reassembly can be
            # checked against text that is known.
            function New-TestChunk {
                param(
                    [int]$ColId,
                    [string]$Text,
                    [int]$KeyColId = -1
                )

                if ($KeyColId -lt 0) {
                    $KeyColId = $ColId
                }

                $plainText = [System.Text.Encoding]::Unicode.GetBytes($Text)
                $keystreamParams = @{
                    FamilyGuid = $chunkFamilyGuid
                    ObjectId   = $chunkObjectId
                    ColId      = $KeyColId
                    Length     = $plainText.Length
                }
                $keystream = & $dbatoolsModule { param($p) Get-EncryptedObjectKeystream @p } $keystreamParams

                $cipher = New-Object byte[] $plainText.Length
                for ($offset = 0; $offset -lt $plainText.Length; $offset++) {
                    $cipher[$offset] = $plainText[$offset] -bxor $keystream[$offset]
                }

                return [PSCustomObject]@{
                    ColId  = $ColId
                    Cipher = $cipher
                }
            }

            function Convert-TestChunk {
                param($Chunk)

                $chunkParams = @{
                    FamilyGuid = $chunkFamilyGuid
                    ObjectId   = $chunkObjectId
                    Chunk      = $Chunk
                }
                return & $dbatoolsModule { param($p) ConvertFrom-EncryptedObjectChunk @p } $chunkParams
            }

            $firstHalf = "CREATE PROCEDURE dbo.Split WITH ENCRYPTION AS "
            $secondHalf = "SELECT 1 AS Id"
        }

        It "Reassembles a definition that is split over two chunks" {
            $chunk = @(
                (New-TestChunk -ColId 1 -Text $firstHalf),
                (New-TestChunk -ColId 2 -Text $secondHalf)
            )
            Convert-TestChunk -Chunk $chunk | Should -BeExactly "$firstHalf$secondHalf"
        }

        It "Reassembles in colid order even when the chunks arrive in reverse" {
            # Concatenating in the order the rows were read would swap the halves, and the result would be
            # exactly the right length, so only comparing the text catches it.
            $chunk = @(
                (New-TestChunk -ColId 2 -Text $secondHalf),
                (New-TestChunk -ColId 1 -Text $firstHalf)
            )
            Convert-TestChunk -Chunk $chunk | Should -BeExactly "$firstHalf$secondHalf"
        }

        It "Does not return the text when a chunk is keyed with the wrong colid" {
            # colid is an input to the key, so one keystream for the whole object would leave the first
            # chunk readable and everything after it mojibake.
            $chunk = @(
                (New-TestChunk -ColId 1 -Text $firstHalf),
                (New-TestChunk -ColId 2 -Text $secondHalf -KeyColId 1)
            )
            Convert-TestChunk -Chunk $chunk | Should -Not -BeExactly "$firstHalf$secondHalf"
        }

        It "Still returns a single chunk definition unchanged" {
            $chunk = @( (New-TestChunk -ColId 1 -Text "$firstHalf$secondHalf") )
            Convert-TestChunk -Chunk $chunk | Should -BeExactly "$firstHalf$secondHalf"
        }

        It "Refuses ciphertext that is not a whole number of characters" {
            # The definition is UCS-2, so an odd byte count cannot be right. Left to the decode it would
            # silently drop the trailing byte and return text that looks plausible.
            $whole = New-TestChunk -ColId 1 -Text $secondHalf
            $odd = New-Object byte[] ($whole.Cipher.Length + 1)
            [Array]::Copy($whole.Cipher, 0, $odd, 0, $whole.Cipher.Length)
            $oddChunk = @(
                [PSCustomObject]@{
                    ColId  = 1
                    Cipher = $odd
                }
            )
            { Convert-TestChunk -Chunk $oddChunk } | Should -Throw -ExpectedMessage "*not a whole number of UCS-2 characters*"
        }
    }

    Context "DAC reuse behavior" {
        It "Should reuse an existing DAC server object without reconnecting or disconnecting it" {
            InModuleScope dbatools {
                function Test-FunctionInterrupt { $false }
                function Get-DbaSpConfigure {
                    [PSCustomObject]@{
                        ConfiguredValue = 1
                    }
                }
                function Connect-DbaInstance { throw "Connect-DbaInstance should not be called for an existing DAC connection." }
                function Disconnect-DbaInstance { throw "Disconnect-DbaInstance should not be called for a reused DAC connection." }
                function Stop-Function {
                    param($Message, $ErrorRecord)
                    throw "$Message | inner: $($ErrorRecord.Exception.Message)"
                }
                function Write-Message { }

                $mockServer = New-Object Microsoft.SqlServer.Management.Smo.Server "sql1"
                $mockServer.ConnectionContext.ServerInstance = "ADMIN:sql1"
                $mockServer | Add-Member -NotePropertyName Databases -NotePropertyValue @() -Force
                $mockInstance = [DbaInstanceParameter]"sql1"
                $field = [DbaInstanceParameter].GetField("InputObject", [System.Reflection.BindingFlags]"NonPublic,Public,Instance,FlattenHierarchy")
                $field.SetValue($mockInstance, $mockServer)

                $mockInstance.Type | Should -Be "Server"
                $mockInstance.InputObject.ConnectionContext.ServerInstance | Should -Match "^ADMIN:"

                $null = Invoke-DbaDbDecryptObject -SqlInstance $mockInstance -Database "master"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Type Container -Path $tempDir

        # Get a random value for the database name
        $random = Get-Random

        # Setup the database name
        $dbname = "dbatoolsci_decrypt_$random"

        # Create the database
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $dbname

        if ($null -ne $TestConfig.SQLUserName) {
            $securePassword = ConvertTo-SecureString -String $TestConfig.SQLPassword -AsPlainText -Force
            $sqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $TestConfig.SQLUserName, $securePassword
        }

        $InstanceMulti2Db = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -Name $dbname

        # test object for usage with sql credential
        $remoteDacSampleEncryptedView = "CREATE VIEW dbo.dbatoolsci_test_remote_dac_vw WITH ENCRYPTION AS SELECT 'remoteDac' as TestFeature;"
        $InstanceMulti2Db.Query($remoteDacSampleEncryptedView)

        # Setup the code for the encrypted function
        $queryScalarFunction = "
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted scalar function to test the command
-- =============================================
CREATE FUNCTION dbo.DummyEncryptedScalarFunction
(
    @param1 varchar(100)
)
RETURNS VARCHAR
WITH ENCRYPTION
AS
BEGIN
    -- Declare the return variable here
    DECLARE @ResultVar VARCHAR(100)

    -- Add the T-SQL statements to compute the return value here
    SELECT @ResultVar = 'Hello this is a test function' + @param1

    -- Return the result of the function
    RETURN @ResultVar

END
        "
        # Create the encrypted scalar function
        $db.Query($queryScalarFunction)

        # Setup the code for the encrypted inline function
        $queryInlineTVF = "
CREATE FUNCTION dbo.DummyEncryptedInlineTVF
(
    @Id INTEGER
)
RETURNS TABLE
WITH ENCRYPTION
AS
    RETURN SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version, @Id AS Id;
        "
        # Create the encrypted inline TVF
        $db.Query($queryInlineTVF)

        # Setup the code for the encrypted table valued function
        $queryTableValuedFunction = "
CREATE FUNCTION dbo.DummyEncryptedTableValuedFunction
(
    @Id INTEGER
)
RETURNS @r TABLE(i INTEGER)
WITH ENCRYPTION
AS
BEGIN
    INSERT INTO @r (i) VALUES (@Id)
    RETURN
END;
        "
        # Create the encrypted table valued function
        $db.Query($queryTableValuedFunction)

        # Setup the query for the encrypted stored procedure
        $queryStoredProcedure = "
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted stored procedure to test the command
-- =============================================
CREATE PROCEDURE dbo.DummyEncryptedStoredProcedure
    @param1 VARCHAR(100)
WITH ENCRYPTION
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON;

    -- Insert statements for procedure here
    SELECT @param1
END
        "

        # Create the encrypted stored procedure
        $db.Query($queryStoredProcedure)

        # Setup a stored procedure with a definition that is far too large to be stored inside the
        # sys.sysobjvalues row, so that reading it back from off row storage is covered as well. At this
        # size the blob root points straight at data pages.
        $queryLargeStoredProcedure = "
CREATE PROCEDURE dbo.DummyEncryptedLargeStoredProcedure
WITH ENCRYPTION
AS
BEGIN
    /* $("A" * 20000) */
    SELECT 1 AS Id
END
        "
        # Create the large encrypted stored procedure
        $db.Query($queryLargeStoredProcedure)

        # And one large enough that the blob root points at an internal node instead of straight at data
        # pages, so that the level of the blob tree in between is covered too. A reader that only handles
        # the flat shape works up to a few hundred kilobytes and then fails.
        $queryTreeStoredProcedure = "
CREATE PROCEDURE dbo.DummyEncryptedTreeStoredProcedure
WITH ENCRYPTION
AS
BEGIN
    /* $("B" * 300000) */
    SELECT 1 AS Id
END
        "
        # Create the encrypted stored procedure that is stored as a blob tree
        $db.Query($queryTreeStoredProcedure)

        # An unencrypted module, to prove it is refused. sys.sysobjvalues holds the text of every module,
        # so a reader pointed at a plain one would XOR its plaintext and return rubbish without failing.
        $queryPlainStoredProcedure = "
CREATE PROCEDURE dbo.DummyPlainStoredProcedure
AS
BEGIN
    SELECT 1 AS Id
END
        "
        # Create the unencrypted stored procedure
        $db.Query($queryPlainStoredProcedure)

        # Setup the code for the encrypted view
        $setupView = "
CREATE VIEW dbo.dbatoolsci_test_vw
WITH ENCRYPTION
AS
SELECT 1 AS Id;"
        # Create the encrypted view
        $db.Query($setupView)

        # Create a schema to test with
        $db.Query("CREATE SCHEMA dbatools")

        # Setup the code for the encrypted trigger
        $setupTable = "
CREATE TABLE dbatools.dbatoolsci_tab1
(
    Id INTEGER
);"
        $db.Query($setupTable)

        $setupTrigger = "
CREATE TRIGGER dbatools.dbatoolsci_test_trigger
ON dbatools.dbatoolsci_tab1
WITH ENCRYPTION
INSTEAD OF DELETE
AS
BEGIN
    RAISERROR ('Invoke-DbaDbDecryptObject.Tests', 16, 10);
END;"
        # Create the encrypted trigger
        $db.Query($setupTrigger)

        # Setup the code for an encrypted view in a schema other than dbo
        $setupViewInSchema = "
CREATE VIEW dbatools.dbatoolsci_test_schema_vw
WITH ENCRYPTION
AS
SELECT 'dbatools' as SchemaName;"
        # Create the encrypted view
        $db.Query($setupViewInSchema)

        # Create another schema to test with
        $db.Query("CREATE SCHEMA dbatools2")

        # Setup the code for an encrypted view in another schema other than dbo
        $setupAnotherViewInSchema = "
CREATE VIEW dbatools2.dbatoolsci_test_schema_vw
WITH ENCRYPTION
AS
SELECT 'dbatools2' as SchemaName;"
        # Create the encrypted view
        $db.Query($setupAnotherViewInSchema)

        # Setup the code for a view that has UTF8 characters
        $setupViewWithUTF8 = "CREATE VIEW dbo.dbatoolsci_test_UTF8_vw
WITH ENCRYPTION
AS
SELECT 'áéíñóú¡¿' as SampleUTF8;"
        # Create the encrypted view
        $db.Query($setupViewWithUTF8)

        # Check if DAC is enabled
        $config = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -ConfigName RemoteDacConnectionsEnabled
        if ($config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -ConfigName RemoteDacConnectionsEnabled -Value $true
        }

        $InstanceMulti2Config = Get-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -ConfigName RemoteDacConnectionsEnabled
        if ($InstanceMulti2Config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -ConfigName RemoteDacConnectionsEnabled -Value $true
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -Database $dbname

        Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

        # Set the original configuration
        if ($config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -ConfigName RemoteDacConnectionsEnabled -Value $false
        }
        if ($InstanceMulti2Config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -ConfigName RemoteDacConnectionsEnabled -Value $false
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "DAC enabled" {
        It "Should throw error" {
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -Name RemoteDacConnectionsEnabled -Value $false
            Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure -WarningVariable warn -WarningAction SilentlyContinue
            $error[0].Exception | Should -BeLike "*DAC is not enabled for instance*"
            Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -Name RemoteDacConnectionsEnabled -Value $true -WarningAction SilentlyContinue
        }
    }

    Context "Decrypt Scalar Function" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedScalarFunction
            $result.Script | Should -Be $queryScalarFunction
        }
    }

    Context "Decrypt Inline TVF" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedInlineTVF
            $result.Script | Should -Be $queryInlineTVF
        }
    }

    Context "Decrypt TVF" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedTableValuedFunction
            $result.Script | Should -Be $queryTableValuedFunction
        }
    }

    Context "Decrypt Stored Procedure" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure
            $result.Script | Should -Be $queryStoredProcedure
        }
    }

    Context "Decrypt view" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_vw
            $result.Script | Should -Be $setupView
        }
    }

    Context "Decrypt trigger in a schema other than dbo" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_trigger
            $result.Script | Should -Be $setupTrigger
        }
    }

    Context "Decrypt objects with the same name but in different schemas" {
        It "Should be successful" {
            @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_schema_vw).Count | Should -Be 2
        }
    }

    Context "Decrypt view with UTF8" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_UTF8_vw -EncodingType UTF8
            $result.Script | Should -Not -BeNullOrEmpty
        }
    }

    Context "Decrypt view and use a destination folder" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_vw -ExportDestination $tempDir
            (Get-Content $result.OutputFile -Raw).Trim() | Should -Be $setupView.Trim()
        }
    }

    Context "Decrypt all encrypted objects and use a destination folder" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ExportDestination $tempDir
            @($result | Where-Object Type -eq "StoredProcedure").Count | Should -Be 3
            @($result | Where-Object Type -eq "Trigger").Count | Should -Be 1
            @($result | Where-Object Type -eq "UserDefinedFunction").Count | Should -Be 3
            @($result | Where-Object Type -eq "View").Count | Should -Be 4
        }
    }

    Context "Decrypt object with an existing DAC connection" {
        It "Should leave the caller DAC connection open" {
            $dacServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -DedicatedAdminConnection -WarningAction SilentlyContinue

            try {
                $null = $dacServer.Query("SELECT 1 AS TestConnection")
                $dacServer.ConnectionContext.SqlConnectionObject.State | Should -Be "Open"

                $result = Invoke-DbaDbDecryptObject -SqlInstance $dacServer -Database $dbname -ObjectName dbatoolsci_test_vw

                $result.Script | Should -Be $setupView
                $dacServer.ConnectionContext.ServerInstance | Should -Match "^ADMIN:"
                $dacServer.ConnectionContext.SqlConnectionObject.State | Should -Be "Open"
            } finally {
                $null = $dacServer | Disconnect-DbaInstance
            }
        }
    }

    Context "Leave the SMO init fields of the caller's connection as they were found" {
        # Finding the encrypted objects would cost a round trip per module without asking SMO to fetch
        # IsEncrypted as part of the enumeration, so the command sets the init fields for the three
        # module types. Those belong to the connection and outlive the command on one the caller owns,
        # which would silently replace a choice the caller had made for the rest of their session.
        It "Should put back init fields the caller had chosen" {
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1

            try {
                # Deliberately not the set the command wants, and deliberately missing IsEncrypted, so a
                # command that failed to restore would leave a difference this can see.
                $callerFields = New-Object System.Collections.Specialized.StringCollection
                [void]$callerFields.AddRange([string[]]@("Name", "Schema", "IsSystemObject"))
                $callerServer.SetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure], $callerFields)

                # Read back rather than compared against what was set, because SMO keeps only the fields
                # it does not always fetch anyway, so the stored value is not the list handed to it.
                $beforeProcedure = @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure])) -join ", "
                $beforeView = @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View])) -join ", "
                $beforeFunction = @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction])) -join ", "

                # The run has to do real work, or a command that returned early would pass this without
                # ever setting the fields it is supposed to put back.
                $result = Invoke-DbaDbDecryptObject -SqlInstance $callerServer -Database $dbname -ObjectName DummyEncryptedStoredProcedure -DataPages
                $result.Script | Should -Be $queryStoredProcedure

                @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.StoredProcedure])) -join ", " | Should -Be $beforeProcedure
                @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.View])) -join ", " | Should -Be $beforeView
                @($callerServer.GetDefaultInitFields([Microsoft.SqlServer.Management.Smo.UserDefinedFunction])) -join ", " | Should -Be $beforeFunction
            } finally {
                $null = $callerServer | Disconnect-DbaInstance
            }
        }
    }

    Context "Decrypt without a dedicated admin connection" {
        It "Should decrypt a stored procedure" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure -DataPages
            $result.Script | Should -Be $queryStoredProcedure
        }

        It "Should decrypt a trigger in a schema other than dbo" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_trigger -DataPages
            $result.Script | Should -Be $setupTrigger
        }

        It "Should decrypt a definition that is stored off row" {
            # A definition of this size does not fit in the sys.sysobjvalues row, so it is reassembled
            # from the blob records that the row points at.
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedLargeStoredProcedure -DataPages
            $result.Script | Should -Be $queryLargeStoredProcedure
        }

        It "Should decrypt a definition whose blob tree has an internal node" {
            # Large enough that the blob root points at an internal node rather than straight at data
            # pages, so the pages are read a level at a time and reassembled depth first. A mistake in
            # that order produces ciphertext of exactly the right length, so only comparing the text
            # against what was submitted catches it.
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedTreeStoredProcedure -DataPages
            $result.Script | Should -Be $queryTreeStoredProcedure
        }

        It "Should not return a module that is not encrypted" {
            # sys.sysobjvalues holds the text of every module, so a reader pointed at a plain one would
            # XOR its plaintext against a keystream and hand back rubbish of a plausible length.
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyPlainStoredProcedure -DataPages
            $result | Should -BeNullOrEmpty
        }

        It "Should return a definition that contains non ASCII characters unchanged" {
            # The definition is stored as UCS-2 and is decoded as such, so no EncodingType is needed and
            # the characters survive, which the method that uses the DAC cannot do.
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_UTF8_vw -DataPages
            $result.Script | Should -Be $setupViewWithUTF8
        }

        It "Should decrypt every encrypted object in the database" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -DataPages
            @($result | Where-Object Type -eq "StoredProcedure").Count | Should -Be 3
            @($result | Where-Object Type -eq "Trigger").Count | Should -Be 1
            @($result | Where-Object Type -eq "UserDefinedFunction").Count | Should -Be 3
            @($result | Where-Object Type -eq "View").Count | Should -Be 4
        }

        It "Should reach the rows by seeking the index rather than scanning every page" {
            # A fallback to the scan would pass every byte exactness check while testing nothing about the
            # seek, so the route actually taken has to be asserted on directly.
            $trace = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure -DataPages -Verbose 4>&1)
            @($trace | Where-Object { "$PSItem" -like "*Seeked the index of sys.sysobjvalues*" }).Count | Should -BeGreaterThan 0
            @($trace | Where-Object { "$PSItem" -like "*Scanned * pages of sys.sysobjvalues*" }).Count | Should -Be 0
        }

        It "Should return the same text by seek, by page list and by page chain" {
            # Three routes to the same rows. The chain walk is the one taken on an instance without
            # sys.dm_db_database_page_allocations, which is what the SQL Server 2005 support rests on, and
            # nothing reaches it by accident on 2012 or later - so it is forced here or it is never tested
            # at all. The routes share almost no code below the row parse, so agreement is real evidence.
            $routeText = InModuleScope dbatools -Parameters @{ DatabaseName = $dbname; Instance = $TestConfig.InstanceMulti1 } {
                $server = Connect-DbaInstance -SqlInstance $Instance
                $db = $server.Databases[$DatabaseName]
                $familyGuidRow = @($db.Query("SELECT family_guid FROM sys.database_recovery_status WHERE database_id = DB_ID()"))
                $familyGuid = [guid]$familyGuidRow[0].family_guid
                $encryptedId = @(@($db.Query("SELECT m.object_id AS ObjectId FROM sys.sql_modules AS m WHERE m.definition IS NULL")) | ForEach-Object { [int]$PSItem.ObjectId })

                $result = @{ }
                foreach ($route in @("Seek", "PageList", "ChainWalk")) {
                    $readParams = @{
                        Database = $db
                        ObjectId = $encryptedId
                    }
                    if ($route -eq "PageList") {
                        $readParams["ForceScan"] = $true
                    }
                    if ($route -eq "ChainWalk") {
                        $readParams["ForceChainWalk"] = $true
                    }

                    $byObject = @{ }
                    foreach ($group in (@(Get-EncryptedObjectImageValue @readParams) | Group-Object -Property ObjectId)) {
                        $chunkParams = @{
                            FamilyGuid = $familyGuid
                            ObjectId   = [int]$group.Name
                            Chunk      = @($group.Group)
                        }
                        $byObject[[int]$group.Name] = ConvertFrom-EncryptedObjectChunk @chunkParams
                    }
                    $result[$route] = $byObject
                }
                $result
            }

            $routeText.Seek.Count | Should -BeGreaterThan 0
            $routeText.PageList.Count | Should -Be $routeText.Seek.Count
            $routeText.ChainWalk.Count | Should -Be $routeText.Seek.Count

            foreach ($objectId in $routeText.Seek.Keys) {
                $routeText.PageList[$objectId] | Should -BeExactly $routeText.Seek[$objectId]
                $routeText.ChainWalk[$objectId] | Should -BeExactly $routeText.Seek[$objectId]
            }
        }

        It "Should return the same text whether the rows were seeked or scanned" {
            # The two routes share almost no code below the row parse - one reads a handful of pages, the
            # other reads every page of the rowset - so agreement is the strongest available evidence that
            # the seek finds the right rows rather than plausible ones.
            $seekResult = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -DataPages

            $scanText = InModuleScope dbatools -Parameters @{ DatabaseName = $dbname; Instance = $TestConfig.InstanceMulti1 } {
                $server = Connect-DbaInstance -SqlInstance $Instance
                $db = $server.Databases[$DatabaseName]
                $familyGuidRow = @($db.Query("SELECT family_guid FROM sys.database_recovery_status WHERE database_id = DB_ID()"))
                $familyGuid = [guid]$familyGuidRow[0].family_guid

                $encryptedId = @($db.Query("SELECT m.object_id AS ObjectId FROM sys.sql_modules AS m WHERE m.definition IS NULL")) | ForEach-Object { [int]$PSItem.ObjectId }

                $scanParams = @{
                    Database  = $db
                    ObjectId  = @($encryptedId)
                    ForceScan = $true
                }
                $scanChunk = @(Get-EncryptedObjectImageValue @scanParams)

                $map = @{ }
                foreach ($group in ($scanChunk | Group-Object -Property ObjectId)) {
                    $chunkParams = @{
                        FamilyGuid = $familyGuid
                        ObjectId   = [int]$group.Name
                        Chunk      = @($group.Group)
                    }
                    $map[[int]$group.Name] = ConvertFrom-EncryptedObjectChunk @chunkParams
                }
                $map
            }

            $scanText.Count | Should -BeGreaterThan 0
            foreach ($item in $seekResult) {
                $scanText.Values | Should -Contain $item.Script
            }
        }

        It "Should succeed while remote dedicated admin connections are disabled" {
            # The whole point of the switch is that no dedicated admin connection is involved, so the
            # configuration that the default method insists on must not be consulted at all.
            try {
                Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -Name RemoteDacConnectionsEnabled -Value $false -WarningAction SilentlyContinue
                $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $dbname -ObjectName dbatoolsci_test_vw -DataPages
                $result.Script | Should -Be $setupView
            } finally {
                Set-DbaSpConfigure -SqlInstance $TestConfig.InstanceMulti1 -Name RemoteDacConnectionsEnabled -Value $true -WarningAction SilentlyContinue
            }
        }
    }

    Context "Decrypt a trigger whose parent is a view" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Its own database, because the method that uses the DAC cannot reach this object at all: it
            # obtains a known plaintext by rewriting the trigger as AFTER INSERT, and a view only accepts
            # INSTEAD OF, so putting it in the shared fixture would break that method's tests. Reading the
            # data pages has no such restriction.
            $viewTriggerDbName = "dbatoolsci_decryptviewtrg_$(Get-Random)"
            $viewTriggerDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $viewTriggerDbName

            $viewTriggerDb.Query("CREATE TABLE dbo.dbatoolsci_trgbase (Id INTEGER);")
            $viewTriggerDb.Query("CREATE VIEW dbo.dbatoolsci_trgview AS SELECT Id FROM dbo.dbatoolsci_trgbase;")

            # A trigger's parent is a table or a view, and a discovery walk that only looks at tables skips
            # the view case silently, which is how a real encrypted trigger went unreturned.
            $queryViewTrigger = "
CREATE TRIGGER dbo.dbatoolsci_test_view_trigger
ON dbo.dbatoolsci_trgview
WITH ENCRYPTION
INSTEAD OF INSERT
AS
BEGIN
    SELECT 1 AS Id;
END;"
            $viewTriggerDb.Query($queryViewTrigger)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $viewTriggerDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should decrypt an encrypted INSTEAD OF trigger defined on a view" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $viewTriggerDbName -DataPages)
            @($result | Where-Object Type -eq "Trigger").Count | Should -Be 1
            @($result | Where-Object Name -eq "dbatoolsci_test_view_trigger")[0].Script | Should -Be $queryViewTrigger
        }

        # An instance allows only one dedicated admin connection, so one that the command leaves behind
        # blocks every later run until the session is killed. This object is the reliable way to reach a
        # failure with that connection already open: the method that uses it rewrites the trigger as
        # AFTER INSERT to obtain a known plaintext, and a view only accepts INSTEAD OF.
        It "Should close the dedicated admin connection it opened when the run fails" {
            { Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $viewTriggerDbName -EnableException } | Should -Throw

            $queryDacSession = @"
SELECT COUNT(*) AS SessionCount
FROM sys.dm_exec_connections
WHERE endpoint_id = (SELECT endpoint_id FROM sys.endpoints WHERE name = 'Dedicated Admin Connection')
"@
            $dacSession = @($viewTriggerDb.Query($queryDacSession))
            $dacSession[0].SessionCount | Should -Be 0
        }
    }

    Context "Decrypt objects whose names contain quoting characters" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Its own database, because the counts asserted against the shared fixture are exact and would
            # change if these objects were added to it.
            $quotingDbName = "dbatoolsci_decryptquoting_$(Get-Random)"
            $quotingDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $quotingDbName

            # An object name may contain a single quote, and the method that uses the DAC put the name in
            # the OBJECT_ID literal of the query that reads the secret and in the EXEC that runs the known
            # plaintext. A name spelling the end of that literal therefore ran whatever followed it as a
            # further statement in the same batch, as sysadmin over the dedicated admin connection, while
            # the command returned as though nothing had happened. This name spells exactly that, so the
            # table it names appearing in the database is the proof the hole is open.
            $injectedTableName = "dbatoolsci_injected_by_name"
            $quotingProcName = "dbatoolsci_quote_'); CREATE TABLE dbo.$injectedTableName (Id INT); --"
            $quotingProcDefinition = "CREATE PROCEDURE dbo.[$quotingProcName] WITH ENCRYPTION AS SELECT 1 AS Id;"
            $quotingDb.Query($quotingProcDefinition)

            # A name may equally contain a closing bracket, which ends the identifier early and leaves the
            # rest of the name standing as statement text in the ALTER that obtains the known plaintext.
            $bracketProcName = "dbatoolsci_bracket_]_proc"
            $bracketProcDefinition = "CREATE PROCEDURE dbo.[$($bracketProcName -replace "\]", "]]")] WITH ENCRYPTION AS SELECT 2 AS Id;"
            $quotingDb.Query($bracketProcDefinition)

            # A trigger names its parent as well as itself, and the parent was interpolated with no
            # brackets at all, so a parent whose name holds a bracket breaks the same statement from the
            # other side.
            $bracketTableName = "dbatoolsci_bracket_]_table"
            $quotingDb.Query("CREATE TABLE dbo.[$($bracketTableName -replace "\]", "]]")] (Id INTEGER);")

            $bracketTriggerDefinition = "CREATE TRIGGER dbo.dbatoolsci_bracket_trigger ON dbo.[$($bracketTableName -replace "\]", "]]")] WITH ENCRYPTION AFTER INSERT AS SELECT 3 AS Id;"
            $quotingDb.Query($bracketTriggerDefinition)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $quotingDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should decrypt them all with a dedicated admin connection and run nothing that a name spells" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $quotingDbName)

            $result.Count | Should -Be 3
            @($result | Where-Object Name -eq $quotingProcName)[0].Script | Should -Be $quotingProcDefinition
            @($result | Where-Object Name -eq $bracketProcName)[0].Script | Should -Be $bracketProcDefinition
            @($result | Where-Object Name -eq "dbatoolsci_bracket_trigger")[0].Script | Should -Be $bracketTriggerDefinition

            $queryInjectedTable = @"
SELECT COUNT(*) AS TableCount FROM sys.tables WHERE name = N'$injectedTableName'
"@
            $injectedTable = @($quotingDb.Query($queryInjectedTable))
            $injectedTable[0].TableCount | Should -Be 0
        }

        It "Should decrypt them all without a dedicated admin connection" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $quotingDbName -DataPages)

            $result.Count | Should -Be 3
            @($result | Where-Object Name -eq $quotingProcName)[0].Script | Should -Be $quotingProcDefinition
            @($result | Where-Object Name -eq $bracketProcName)[0].Script | Should -Be $bracketProcDefinition
            @($result | Where-Object Name -eq "dbatoolsci_bracket_trigger")[0].Script | Should -Be $bracketTriggerDefinition
        }
    }

    Context "Decrypt objects whose schema and name collide when joined into one key" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Its own database, because the counts asserted against the shared fixture are exact and would
            # change if these objects were added to it.
            $collideDbName = "dbatoolsci_decryptcollide_$(Get-Random)"
            $collideDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $collideDbName

            # Both a schema and an object name are allowed to contain a dot, so a lookup that joins them
            # into a single "$schema.$name" string cannot tell schema [a], object [b.c] apart from schema
            # [a.b], object [c]: both key as "a.b.c". Whichever row a name based lookup reads last silently
            # overwrites the other's id in the map, and the object that lost the race is then decrypted
            # with the other one's ciphertext instead of its own.
            $collideDb.Query("CREATE SCHEMA [a]")
            $collideDb.Query("CREATE SCHEMA [a.b]")

            $collideFirstDefinition = "CREATE PROCEDURE [a].[b.c] WITH ENCRYPTION AS SELECT 111 AS Marker;"
            $collideDb.Query($collideFirstDefinition)

            $collideSecondDefinition = "CREATE PROCEDURE [a.b].[c] WITH ENCRYPTION AS SELECT 222 AS Marker;"
            $collideDb.Query($collideSecondDefinition)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $collideDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should decrypt both with a dedicated admin connection, each with its own definition" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $collideDbName)

            $result.Count | Should -Be 2
            @($result | Where-Object { $PSItem.Schema -ceq "a" -and $PSItem.Name -ceq "b.c" })[0].Script | Should -Be $collideFirstDefinition
            @($result | Where-Object { $PSItem.Schema -ceq "a.b" -and $PSItem.Name -ceq "c" })[0].Script | Should -Be $collideSecondDefinition
        }

        It "Should decrypt both without a dedicated admin connection, each with its own definition" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $collideDbName -DataPages)

            $result.Count | Should -Be 2
            @($result | Where-Object { $PSItem.Schema -ceq "a" -and $PSItem.Name -ceq "b.c" })[0].Script | Should -Be $collideFirstDefinition
            @($result | Where-Object { $PSItem.Schema -ceq "a.b" -and $PSItem.Name -ceq "c" })[0].Script | Should -Be $collideSecondDefinition
        }
    }

    Context "Decrypt from a read only database" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Its own database, because the counts asserted against the shared fixture are exact, and
            # because a database cannot be dropped while a snapshot of it exists.
            $snapshotSourceName = "dbatoolsci_decryptsnap_$(Get-Random)"
            $snapshotName = "$($snapshotSourceName)_snap"
            $snapshotSourceDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $snapshotSourceName

            # One definition small enough to live in the sys.sysobjvalues row and one far too large for it,
            # so the read of the row and the walk into off row storage are both covered against a snapshot
            # rather than only the simpler of the two.
            $snapshotSmallDefinition = "CREATE PROCEDURE dbo.dbatoolsci_snap_small WITH ENCRYPTION AS SELECT 1 AS Id;"
            $snapshotSourceDb.Query($snapshotSmallDefinition)

            $snapshotLargeDefinition = "CREATE PROCEDURE dbo.dbatoolsci_snap_large WITH ENCRYPTION AS BEGIN /* $("A" * 20000) */ SELECT 2 AS Id; END;"
            $snapshotSourceDb.Query($snapshotLargeDefinition)

            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceMulti1 -Database $snapshotSourceName -Name $snapshotName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceMulti1 -Snapshot $snapshotName -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $snapshotSourceName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        # A snapshot is read only, so the default method cannot reach these objects at all: it obtains a
        # known plaintext by altering the object, which the database refuses. Reading the data pages writes
        # nothing, which is what makes a read only database one of the two cases that need -DataPages. The same
        # holds for an availability group readable secondary, which no test instance here can provide.
        It "Should decrypt in row and off row definitions from a database snapshot" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $snapshotName -DataPages)

            $result.Count | Should -Be 2
            @($result | Where-Object Name -eq "dbatoolsci_snap_small")[0].Script | Should -Be $snapshotSmallDefinition
            @($result | Where-Object Name -eq "dbatoolsci_snap_large")[0].Script | Should -Be $snapshotLargeDefinition
        }
    }

    Context "Decrypt across more than one database in a single call" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Two databases holding an object of the SAME schema and name. That is the case that goes wrong
            # when the object list is not reset per database: the first database's objects get looked up
            # again in the second, so the object is either returned twice or attributed to the wrong
            # database. Same-named objects are what makes it visible rather than silently skipped.
            $pairDbName = @("dbatoolsci_decryptpair1_$(Get-Random)", "dbatoolsci_decryptpair2_$(Get-Random)")
            $pairDefinition = New-Object System.Collections.Hashtable

            foreach ($name in $pairDbName) {
                $pairDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $name
                $pairDefinition[$name] = "CREATE PROCEDURE dbo.DummyEncryptedSharedName WITH ENCRYPTION AS SELECT $($name.Length) AS Id"
                $pairDb.Query($pairDefinition[$name])
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $pairDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should return each database's own copy of a same-named object exactly once" {
            $result = @(Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $pairDbName -DataPages)
            $result.Count | Should -Be 2

            foreach ($name in $pairDbName) {
                $forDatabase = @($result | Where-Object Database -eq $name)
                $forDatabase.Count | Should -Be 1
                $forDatabase[0].Script | Should -Be $pairDefinition[$name]
            }
        }
    }

    Context "Decrypt a definition whose blob tree is several levels deep" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # This one gets a database of its own. A definition this size is only reachable without a
            # dedicated admin connection: the default method pads a known plaintext to the length of the
            # ciphertext, so putting it in the shared fixture would make that method build an ALTER
            # statement of about eight megabytes for no benefit.
            $deepDbName = "dbatoolsci_decryptdeep_$(Get-Random)"
            $deepDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $deepDbName

            # About 4 MB of definition, which is what forces a blob tree with an internal node above
            # another internal node. A reader written against the two level shape works up to a few
            # hundred kilobytes and then fails, so this is the case that catches it.
            $queryDeepStoredProcedure = "
CREATE PROCEDURE dbo.DummyEncryptedDeepStoredProcedure
WITH ENCRYPTION
AS
BEGIN
    /* $("D" * 4000000) */
    SELECT 1 AS Id
END
        "
            $deepDb.Query($queryDeepStoredProcedure)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $deepDbName -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should decrypt a definition stored across several levels of blob tree" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti1 -Database $deepDbName -ObjectName DummyEncryptedDeepStoredProcedure -DataPages
            $result.Script | Should -Be $queryDeepStoredProcedure
        }
    }

    Context "Connect to an instance (ideally a remote instance) using a SqlCredential and decrypt an object" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $TestConfig.InstanceMulti2 -SqlCredential $sqlCredential -Database $dbname -ObjectName dbatoolsci_test_remote_dac_vw -ExportDestination $tempDir
            (Get-Content $result.OutputFile -Raw).Trim() | Should -Be $remoteDacSampleEncryptedView.Trim()
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "The connection of the caller is left in the database it was in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_decrypt_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $contextDbName

            $contextProcName = "dbatoolsci_ctx_secret"
            $splatCreateProc = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $contextDbName
                Query       = "EXEC ('CREATE PROCEDURE dbo.$contextProcName WITH ENCRYPTION AS SELECT 1');"
            }
            $null = Invoke-DbaQuery @splatCreateProc

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection
            $contextBefore = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # -DataPages, because that path reads the definitions from the data pages and needs no dedicated
            # admin connection - the command would otherwise open a connection of its own and the connection
            # of the caller would never be touched.
            $splatDecrypt = @{
                SqlInstance = $callerServer
                Database    = $contextDbName
                ObjectName  = $contextProcName
                DataPages   = $true
            }
            $contextResult = Invoke-DbaDbDecryptObject @splatDecrypt

            $contextAfter = $callerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $contextDbName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "still decrypts the procedure" {
            # Only a command that really did the work can move the connection, so without this the
            # assertion below would pass for the wrong reason.
            $contextResult.Script | Should -BeLike "*CREATE PROCEDURE*"
        }

        It "leaves the connection in the database it was in" {
            $contextAfter | Should -Be $contextBefore
        }
    }
}
