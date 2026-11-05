$vm = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='Win11'"
$vsms = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService

$res = Invoke-CimMethod -InputObject $vsms -MethodName GetVirtualSystemThumbnailImage -Arguments @{
    TargetSystem = $vm
    WidthPixels = 1920
    HeightPixels = 1080
}

if ($res.ImageData) {
    Write-Host "Success! Got thumbnail bytes: $($res.ImageData.Length)"
    [System.IO.File]::WriteAllBytes("scratch/hyperv_screen.raw", $res.ImageData)
} else {
    Write-Host "No image data returned."
}
