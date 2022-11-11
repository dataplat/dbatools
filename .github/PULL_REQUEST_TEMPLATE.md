<!-- Below information IS REQUIRED with every PR -->
## Please read -- recent changes to our repo
On November 10, 2022, [we removed some bloat from our repository (for the second and final time)](https://github.com/dataplat/dbatools/issues/8542). This change requires that all contributors reclone or reset their repo using the following code:

```
git fetch
git reset --hard origin/master
```

You can also just delete your dbatools directory and have GitHub Desktop reclone it.

 - [ ] Please confirm you have the smaller repo (85MB .git directory vs 275MB or 110MB .git directory)

## Type of Change
<!-- What type of change does your code introduce -->
 - [ ] Bug fix (non-breaking change, fixes #<!--issue number--> )
 - [ ] New feature (non-breaking change, adds functionality, fixes #<!--issue number--> )
 - [ ] Breaking change (effects multiple commands or functionality, fixes #<!--issue number--> )
 - [ ] Ran manual Pester test and has passed (`.\tests\manual.pester.ps1`)
 - [ ] Adding code coverage to existing functionality
 - [ ] Pester test is included
 - [ ] If new file reference added for test, has is been added to github.com/dataplat/appveyor-lab ?
 - [ ] Unit test is included
 - [ ] Documentation
 - [ ] Build system

<!-- Below this line you can erase anything that is not applicable -->
### Purpose
<!-- What is the purpose or goal of this PR? (doesn't have to be an essay) -->

### Approach
<!-- How does this change solve that purpose -->

### Commands to test
<!-- if these are the examples in the help just note it as such -->

### Screenshots
<!-- pictures say a thousand words without typing any of it -->

### Learning
<!-- Optional -->
<!--
	Include:
	 - blog post that may have assisted in writing the code
	 - blog post that were initial source
	 - special or unique approach made to solve the problem
-->
