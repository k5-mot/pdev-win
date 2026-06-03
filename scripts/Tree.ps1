Param(
    [Parameter()][String]$Path = (Convert-Path .) ,
    [Parameter()][int]$Depth = 99
)
Write-Host
Write-Host "---------------------------------------"
Write-Host "対象パス："$Path
Write-Host "深さ："$Depth
Write-Host "---------------------------------------"
$Output =""
function GetAclAndChildDirRoot($RootDir){

    Write-Host (Split-Path -Leaf $RootDir)
    $Children = Get-ChildItem -Path $RootDir -Force -Directory | select-object fullname
    foreach ($Child in $Children) {
        $i = 1
        GetAclAndChildDir $Child.FullName $i
    }
}

function GetAclAndChildDir($CurrentTarget,$i){

    if($i -gt $Depth){
        return;
    }
    $Output=""
    for($j=0;$j -lt $i;$j++){
        $Output+=" "
    }

    $Output+=Split-Path -Leaf $CurrentTarget
    Write-Host $Output

    $children = Get-ChildItem -Path $CurrentTarget -Force -Directory | select-object fullname
    $i++
    foreach ($child in $children) {
        GetAclAndChildDir $child.FullName $i
    }
}


GetAclAndChildDirRoot $Path
Write-Host "---------------------------------------"
Read-Host
