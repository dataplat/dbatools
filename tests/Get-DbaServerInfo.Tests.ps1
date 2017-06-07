Describe "Get-DbaServerInfo Developer Test" -Tags DevTest {
	# InModuleScope dbatools {

	# }
	$params = (Get-ChildItem function:\Get-DbaServerInfo).Parameters
	it "should have a parameter named Computer" {
		$params | Should Contain "Computer"
	}
}