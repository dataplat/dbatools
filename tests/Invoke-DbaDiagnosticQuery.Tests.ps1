# test ouput directory to confirm creation of test files
$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. (Join-path (($PSScriptRoot, '.\' -ne '')[0]) "constants.ps1")  #if running in interactive console, cd to folder and you can run this without error
write-host "loaded constants"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
	BeforeAll {
		$script:PesterOutputPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
		[io.directory]::CreateDirectory($script:PesterOutputPath) > $null

		$database = "dbatoolsci_frk_$(Get-Random)"
		$database2 = "dbatoolsci_frk_$(Get-Random)"
		$server = Connect-DbaInstance -SqlInstance $script:instance2
		$server.Query("CREATE DATABASE $database")
		$server.Query("CREATE DATABASE $database2")

	}
	AfterAll {
		$server.Query("ALTER DATABASE $database SET OFFLINE WITH ROLLBACK IMMEDIATE")
		$server.Query("DROP DATABASE IF EXISTS $database")
		$server.Query("ALTER DATABASE $database2 SET OFFLINE WITH ROLLBACK IMMEDIATE")
		$server.Query("DROP DATABASE IF EXISTS $database2")

		Remove-Item $script:PesterOutputPath -recurse #clear test folder contents

	}
	AfterEach {
		Remove-Item "$script:PesterOutputPath\*" -Recurse #clear test folder contents

	}


	Context "verifying output when running queries" {
		It "runs a specific query" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage'
			@($results).Count | Should -Be 1
		}
		It "works with DatabaseSpecific" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific
			@($results).count | Should -BeGreaterThan 10
		}
	}

	context "verifying output when exporting queries as files instead of running" {
		It "exports queries to sql files without running" {
			Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -QueryName 'Memory Clerk Usage' -OutputPath $script:PesterOutputPath
			@(Get-ChildItem -path $script:PesterOutputPath -filter *.sql).Count | Should -be 1
		}

		It "returns pscustomobject[] containing parsed queries" {
			[System.Management.Automation.PSObject[]]$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -whatif
			@($results).count | Should -BeGreaterThan 10

			#verifying the data types returned are consistent with an array of pscustom customobjects to allow working with the queries further if needed
			#this also ensures that any "whatif" is not polluting the output stream with objects
			# for better understanding on why I'm using write-output to validate  type, see: https://github.com/pester/Pester/issues/38

			write-debug "Note that to match , results have to be declared as above, explicitly psobject, otherwise just Object[] array"
			Write-Output -NoEnumerate $results | Should -BeOfType [System.Management.Automation.PSObject[]]
			if ($DebugPreference -ne 'silentlycontinue') {  $results | foreach-object { write-debug "foreach-object in `$results - UnderlyingSystemType $($_.GetType().UnderlyingSystemType)" } }
			$results | foreach-object {
				Write-Output -NoEnumerate $_ | Should -BeOfType  [System.Management.Automation.PSCustomObject]
			}
		}

		It "exports single database specific query against single database" {
			Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -queryname 'Database-scoped Configurations' -databasename $database -OutputPath $script:PesterOutputPath
			@(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | where {$_.FullName -match "($database)"}).Count | should -be 1
		}

		It "exports a database specific query foreach specific database provided" {
			Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2  -ExportQueries  -DatabaseSpecific -queryname 'Database-scoped Configurations' -databasename @($database, $database2) -OutputPath $script:PesterOutputPath
			@(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | where {$_.FullName -match "($database)|($database2)"}).Count | should -be 2
		}

		It "exports database specific query when multiple specific databases are referenced" {
			Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -ExportQueries -DatabaseSpecific -queryname 'Database-scoped Configurations' -OutputPath $script:PesterOutputPath
			@(Get-ChildItem -path $script:PesterOutputPath -filter *.sql | where {$_.FullName -match "($database)|($database2)"}).Count | should -Be 2
		}

	}

	context "verifying output when running database specific queries" {
		It "runs database specific queries against single database only when providing database name" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -queryname 'Database-scoped Configurations' -databasename $database
			@($results).Count | should -be 1
		}

		It "runs database specific queries against set of databases when provided with multiple database names" {
			$results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -DatabaseSpecific -queryname 'Database-scoped Configurations' -databasename @($database, $database2)
			@($results).Count |  should -be 2
		}
	}


}
