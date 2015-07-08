# Fetch updates script# version 3.0

# Before running this script the $gits variable should be defined with an array of repos and branches. We should also know where to put the repos

if ( ((Test-Path variable:gits) -ne $True) -or ( (Test-Path variable:gitDeployLocation) -ne $True) )
{
    echo "Couldn't continue because we didn't have either a set of repos, or a git-deploy location"
}
else
{

# Perform fetch on all git repositories
# If the deployment repo has a root file named "_WINDOWS-SERVICE-NAME" with an xml description of the service, 
#  a windows service of the same name will be stopped before
#  the update is applied, and started afterwards



$gits | %{
    $repoRemotePath = $_.Repo
    $repoBranch = $_.Branch
    $repoLocalFolder = $_.Folder
    $repoLocalPath = "$gitDeployLocation\$repoLocalFolder"
    $repoWasCloned = $False
    echo "-------------------------------------"
    echo "$repoLocalFolder on branch $repoBranch"
    echo "-------------------------------------"
    
    #Clone the repo if not exist yet
    if ((test-path "$repoLocalPath\.git") -ne $True)
    {
        echo "Cloning to $repoLocalPath..."
        git clone $repoRemotePath -b $repoBranch $repoLocalPath
        echo "...clone complete."
        $repoWasCloned = $True
    }

    #only proceed if we have a repo
    if (test-path "$repoLocalPath\.git")
    {
        echo "Performing fetch"
        cd $repoLocalPath
        
		$gitFetchStatus = ''
		git fetch 2>&1 | Tee-Object -var gitFetchStatus
		#TODO: make sure the fetch command only gets the current tracked branch, otherwise introduce tighter ref spec
		
		echo "Fetch on origin/$repoBranch completed"
		if  ( ($repoWasCloned -eq $True) -or (![system.string]::IsNullOrEmpty($gitFetchStatus)) )
		{
			echo "Updates were found. Performing a clean, reset and merge"
			
            #Attempt to detect whether this should be a windows service. We must check at this point, before
            # we have updated the working directory, as files may be in use by the service.
            # This means if the service name element has just been added, the next update will cause
            # the service to be stopped and started
            $winService = $null
            $winServiceShouldStart = $True
            if (test-path "_WINDOWS-SERVICE-NAME")
			{
                #deployment is a windows service, if installed then stop and start the service
                
                [xml]$serviceDefinitionRaw = get-content -path _WINDOWS-SERVICE-NAME
                $serviceDefinition = $serviceDefinitionRaw.service
                echo "Deployment repository is a Windows Service with name:"$serviceDefinition.name.toString()
				
				if  (![system.string]::IsNullOrEmpty($serviceDefinition.name.toString()))
				{
                    #get windows service object
                    echo "Retreiving existing service details if any..."
                    $winService = Get-Service $serviceDefinition.name.toString()
                    if (($winService -eq $null) -and ($serviceDefinition.autoCreate -eq $True))
                    {
                        echo "service does not exist and we should create it. Running command..."
                        $currentRepoPath = Get-Location -PSProvider FileSystem
                        if ($serviceDefinition.autoStart -eq $True)
                        {
                            sc.exe create $serviceDefinition.name.toString() start= auto binpath=  ("$currentRepoPath\" + $serviceDefinition.binPath.toString())
                        }
                        else
                        {
                            sc.exe create $serviceDefinition.name.toString() binpath=  ("$currentRepoPath\" + $serviceDefinition.binPath.toString())
                        }
                        #set failure options
						sc.exe failure $serviceDefinition.name.toString() reset= 5 actions= restart/10000
						
                        #only start the service after creation if the service is specified to be auto-start
                        $winServiceShouldStart = $serviceDefinition.autoStart
                        
                        $winService = Get-Service $serviceDefinition.name.toString()
                        if ($winService -eq $null)
                        {
                            echo "Failed to create service"
                        }
                    }
                    elseif (($winService -ne $null) -and ($winService.status -ne "Running"))
                    {
                        #if service was already installed but has been stopped, don't start it later
						#PM - 2012-05-11 Force start, new decision!
                        echo "Service exists but was not started, will not attempt to start after update"
                        $winServiceShouldStart = $True
                    }

                    if ($winService -ne $null)
                    {
                        if ($winService.status -eq "Running")
                        {
                            $msg = [string]::format("Service exists and is Running, stopping service with name [{0}]",$serviceDefinition.name.toString())
                            echo $msg
					        Stop-Service -name $serviceDefinition.name.toString()
                        }
                    }

				}
                else
                {
                    echo "Service name was empty"
                }
			}
            else
            {
                echo "Deployment repository was not for a Windows Service"
            }

			echo "Applying changes to build"
			
            #get rid of any bad files / state we may have
            git clean -f -d
			#git reset --hard head
            #make sure we're on the correct branch
            #git checkout $repoBranch
            #fast-forward to latest origin commit on this branch
			#git merge origin/$repoBranch
            #just make sure
			git reset --hard origin/$repoBranch
            #we need to clean again to get rid of empty directories leftover
            git clean -f -d
			
			if ($?)
			{
				echo "Changed succesfully applied"
			}
			else
			{
				echo "Failed to apply changes!!"
			}
			
			#TODO: we have got changes which may have involved the service definition file...
			#		we should read this file again (or for the 1st time) and see if there are any changes.
			#		For example, the service name may have changed, or there may be a service, where previously
			#			we didn't know about it because we didn't even have any files from the repo, including the service definition file.

			if (($winService -ne $null) -and ($winServiceShouldStart -eq $True))
			{
                #deployment is a windows service, and we should start it
                echo "Starting service with name:"$winService.name.toString()
				Start-Service -name $serviceDefinition.name.toString()
			}
            
            #clean up
            Remove-Variable winService -ErrorAction SilentlyContinue;
            Remove-Variable serviceDefinitionRaw -ErrorAction SilentlyContinue;
            Remove-Variable serviceDefinition -ErrorAction SilentlyContinue;
            Remove-Variable repoRemotePath -ErrorAction SilentlyContinue;
            Remove-Variable repoBranch -ErrorAction SilentlyContinue;
            Remove-Variable repoLocalFolder -ErrorAction SilentlyContinue;
            Remove-Variable repoLocalPath -ErrorAction SilentlyContinue;
            Remove-Variable repoWasCloned -ErrorAction SilentlyContinue;
		}				
		else
		{
			echo "No changes."
		}

        cd ..        
    }
    echo "-------------------------------------"
}
}
