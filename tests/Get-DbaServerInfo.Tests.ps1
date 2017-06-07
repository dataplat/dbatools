Describe "Get-DbaServerInfo - Parmeter Validation" -Tags Unittests {
	InModuleScope dbatools {
		$params = (Get-ChildItem function:\Get-DbaServerInfo).Parameters	
		it "should have a parameter named ComputerName" {
			$params.ContainsKey("ComputerName") | Should Be $true
		}
		it "should have a parameter named Credential" {
			$params.ContainsKey("Credential") | Should Be $true
		}
		it "should have a parameter named Silent" {
			$params.ContainsKey("Silent") | Should Be $true
		}
	}
}