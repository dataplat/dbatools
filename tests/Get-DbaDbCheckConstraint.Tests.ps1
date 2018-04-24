$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.
            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
        #>
        $paramCount = 8
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbCheckConstraint).Parameters.Keys
		$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException', 'Database', 'ExcludeDatabase', 'Table', 'ExcludeTable', 'ExcludeSystemTable'
        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
	BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
		$random = Get-Random
		$tableName = "dbatools_getdbtbl1"
		$tableName2 = "dbatools_getdbtbl2"
        $ckName = "dbatools_getdbck"
        $dbname = "dbatoolsci_getdbfk$random"
        $server.Query("CREATE DATABASE $dbname")
		$server.Query("CREATE TABLE $tableName (idTbl1 INT)", $dbname)
		$server.Query("CREATE TABLE $tableName2 (idTbl2 INT, idTbl1 INT, id3 INT)", $dbname)
		$server.Query("ALTER TABLE $tableName2 ADD CONSTRAINT $ckName CHECK (id3 > 10)", $dbname)
    }

	AfterAll {
		$null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
	}

	Context "Can get table check constraints" {
		It "returns no check constraints from excluded DB with -ExcludeDatabase" {
			$results = Get-DbaDbCheckConstraint -SqlInstance $script:instance2 -ExcludeDatabase master
			$results.where( {$_.Database -eq 'master'}).count | Should Be 0
		}
		It "returns only check constraints from selected DB with -Database" {
			$results = Get-DbaDbCheckConstraint -SqlInstance $script:instance2 -Database $dbname
			$results.where( {$_.Database -ne 'master'}).count | Should Be 1
		}
		It "returns no check constraints with -ExcludeTable" {
			$results = Get-DbaDbCheckConstraint -SqlInstance $script:instance2 -ExcludeTable $tableName2
			$results.count | Should Be 0
		}
		It "returns check constraints without -ExcludeTable" {
			$results = Get-DbaDbCheckConstraint -SqlInstance $script:instance2
			$results.count | Should BeGreaterThan 0
		}
	}
}