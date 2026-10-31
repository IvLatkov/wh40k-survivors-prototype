# Offline extraction only. Never called by the game. Original road.png is read-only.
# Coordinates refer to the inspected 1536x1024 RGBA sheet. No generated artwork.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$folder = Join-Path $root 'assets/art/effects/terrain/roads'
$output = Join-Path $folder 'prepared'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class RoadPreparation {
    static Bitmap Crop(Bitmap source,int left,int top) {
        var result=new Bitmap(256,256,PixelFormat.Format32bppArgb);
        for(int y=0;y<256;y++) for(int x=0;x<256;x++) {
            if(left+x>=source.Width || top+y>=source.Height) continue;
            var c=source.GetPixel(left+x,top+y);
            // Remove the sheet's low-alpha presentation haze, preserve retained RGB.
            if(c.A>=200) result.SetPixel(x,y,Color.FromArgb(255,c.R,c.G,c.B));
        }
        return result;
    }
    static int Turn(int mask) { return ((mask<<1)&15)|(mask>>3); }
    static void RemoveIslands(Bitmap tile) {
        var visited=new bool[65536];
        var largest=new System.Collections.Generic.List<int>();
        for(int start=0;start<65536;start++) {
            if(visited[start] || tile.GetPixel(start%256,start/256).A==0) continue;
            var component=new System.Collections.Generic.List<int>();
            var queue=new System.Collections.Generic.Queue<int>();queue.Enqueue(start);visited[start]=true;
            while(queue.Count>0) {
                int p=queue.Dequeue();component.Add(p);
                int[] next={p-256,p+256,p%256>0?p-1:-1,p%256<255?p+1:-1};
                foreach(int n in next) if(n>=0 && n<65536 && !visited[n] && tile.GetPixel(n%256,n/256).A>0) {visited[n]=true;queue.Enqueue(n);}
            }
            if(component.Count>largest.Count) largest=component;
        }
        var keep=new bool[65536];foreach(int p in largest)keep[p]=true;
        for(int p=0;p<65536;p++) if(!keep[p]) tile.SetPixel(p%256,p/256,Color.Transparent);
    }
    static void CheckPorts(Bitmap tile,int mask) {
        int[] ports={128,128*256+255,255*256+128,128*256};
        var visited=new bool[65536];var queue=new System.Collections.Generic.Queue<int>();
        for(int d=0;d<4;d++) if((mask&(1<<d))!=0) {queue.Enqueue(ports[d]);visited[ports[d]]=true;break;}
        while(queue.Count>0) {
            int p=queue.Dequeue();
            int[] next={p-256,p+256,p%256>0?p-1:-1,p%256<255?p+1:-1};
            foreach(int n in next) if(n>=0 && n<65536 && !visited[n] && tile.GetPixel(n%256,n/256).A>0) {visited[n]=true;queue.Enqueue(n);}
        }
        for(int d=0;d<4;d++) {
            bool expected=(mask&(1<<d))!=0;
            if((tile.GetPixel(ports[d]%256,ports[d]/256).A>0)!=expected || (expected && !visited[ports[d]]))
                throw new Exception("Disconnected silhouette for mask "+mask+", direction "+d);
        }
    }
    public static void Run(string folder,string output) {
        using(var source=new Bitmap(System.IO.Path.Combine(folder,"road.png"))) {
            // N=1,E=2,S=4,W=8. Straight, real NW curve, real T, real cross, real broken end.
            int[] masks={5,9,14,15,8};
            int[,] crops={{22,100},{1272,192},{140,407},{644,523},{528,800}};
            using(var canonical=Crop(source,22,100)) {
                var completed=new System.Collections.Generic.HashSet<int>();
                for(int piece=0;piece<masks.Length;piece++) using(var tile=Crop(source,crops[piece,0],crops[piece,1])) {
                    RemoveIslands(tile);
                    int mask=masks[piece];
                    for(int turn=0;turn<4;turn++) {
                        if(completed.Add(mask)) using(var prepared=(Bitmap)tile.Clone()) {
                            // Shared 24px join collars are copied from the same original
                            // straight. Equal edge texels eliminate cracks between crops.
                            for(int direction=0;direction<4;direction++) {
                                if((mask&(1<<direction))==0) continue;
                                for(int depth=0;depth<24;depth++) for(int across=0;across<256;across++) {
                                    int x=across,y=depth;
                                    if(direction==1){x=255-depth;y=across;}
                                    if(direction==2){x=across;y=255-depth;}
                                    if(direction==3){x=depth;y=across;}
                                    // Use identical rows at the very edge of both sides.
                                    var c=canonical.GetPixel(across,128+depth);
                                    prepared.SetPixel(x,y,c);
                                }
                            }
                            CheckPorts(prepared,mask);
                            prepared.Save(System.IO.Path.Combine(output,"road_"+mask.ToString("00")+".png"),ImageFormat.Png);
                        }
                        tile.RotateFlip(RotateFlipType.Rotate90FlipNone);mask=Turn(mask);
                    }
                }
            }
        }
    }
}
'@
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $roadHash = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes((Join-Path $folder 'road.png')))).Replace('-','').ToLowerInvariant()
    if ($roadHash -ne '1eae96eebc904c5b94cf81cbf1d10bea85698054c3da53eb3e904ff7981d4523') { throw 'Unexpected source sheet; inspect before extracting.' }
    [RoadPreparation]::Run($folder,$output)
    Write-Output "Source SHA256: $roadHash"
} finally {
    $sha.Dispose()
}
