# Prepare shader DATA, not road artwork. Read existing prepared PNGs unchanged.
# No runtime invocation. Preserve internal cracks; fade only exterior soil edges.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$folder = Join-Path $root 'assets/art/effects/terrain/roads/prepared'
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
public static class RoadBlendPreparation {
    const int Size=256;
    const float Width=16f;
    static Bitmap Field(Bitmap road,int mask) {
        var exterior=new bool[Size*Size];
        var pending=new Queue<int>();
        for(int y=0;y<Size;y++) for(int x=0;x<Size;x++) {
            if((x==0||y==0||x==255||y==255) && road.GetPixel(x,y).A==0) {
                int p=y*Size+x;exterior[p]=true;pending.Enqueue(p);
            }
        }
        while(pending.Count>0) {
            int p=pending.Dequeue();
            int[] next={p-256,p+256,p%256>0?p-1:-1,p%256<255?p+1:-1};
            foreach(int n in next) if(n>=0 && n<65536 && !exterior[n] && road.GetPixel(n%256,n/256).A==0) {
                exterior[n]=true;pending.Enqueue(n);
            }
        }
        var distance=new float[65536];
        for(int y=0;y<Size;y++) for(int x=0;x<Size;x++) {
            int p=y*Size+x;distance[p]=exterior[p]?0:1000;
            // Treat a closed sprite edge as exterior. Open ports continue into
            // their neighbor, so never fade the road across that tile border.
            if((y==0&&(mask&1)==0)||(x==255&&(mask&2)==0)||(y==255&&(mask&4)==0)||(x==0&&(mask&8)==0))
                distance[p]=Math.Min(distance[p],1);
        }
        for(int y=0;y<Size;y++) for(int x=0;x<Size;x++) {
            int p=y*Size+x;
            if(x>0)distance[p]=Math.Min(distance[p],distance[p-1]+1);
            if(y>0)distance[p]=Math.Min(distance[p],distance[p-256]+1);
            if(x>0&&y>0)distance[p]=Math.Min(distance[p],distance[p-257]+1.414214f);
            if(x<255&&y>0)distance[p]=Math.Min(distance[p],distance[p-255]+1.414214f);
        }
        for(int y=255;y>=0;y--) for(int x=255;x>=0;x--) {
            int p=y*Size+x;
            if(x<255)distance[p]=Math.Min(distance[p],distance[p+1]+1);
            if(y<255)distance[p]=Math.Min(distance[p],distance[p+256]+1);
            if(x<255&&y<255)distance[p]=Math.Min(distance[p],distance[p+257]+1.414214f);
            if(x>0&&y<255)distance[p]=Math.Min(distance[p],distance[p+255]+1.414214f);
        }
        var field=new Bitmap(Size,Size,PixelFormat.Format32bppArgb);
        for(int y=0;y<Size;y++) for(int x=0;x<Size;x++) {
            float t=Math.Min(1,distance[y*Size+x]/Width);
            int value=(int)Math.Round(255*t*t*(3-2*t));
            field.SetPixel(x,y,Color.FromArgb(255,value,value,value));
        }
        return field;
    }
    public static void Run(string folder) {
        var fields=new Bitmap[16];
        try {
            using(var atlas=new Bitmap(1280,768,PixelFormat.Format32bppArgb)) {
                for(int mask=1;mask<16;mask++) using(var road=new Bitmap(System.IO.Path.Combine(folder,"road_"+mask.ToString("00")+".png"))) {
                    fields[mask]=Field(road,mask);
                    int ox=(mask-1)%5*256,oy=(mask-1)/5*256;
                    for(int y=0;y<256;y++)for(int x=0;x<256;x++) atlas.SetPixel(ox+x,oy+y,fields[mask].GetPixel(x,y));
                }
                for(int a=1;a<16;a++)for(int b=1;b<16;b++)for(int p=0;p<256;p++) {
                    if((a&2)!=0 && (b&8)!=0 && fields[a].GetPixel(255,p)!=fields[b].GetPixel(0,p)) throw new Exception("E/W fringe seam");
                    if((a&4)!=0 && (b&1)!=0 && fields[a].GetPixel(p,255)!=fields[b].GetPixel(p,0)) throw new Exception("N/S fringe seam");
                }
                atlas.Save(System.IO.Path.Combine(folder,"road_edge_masks.png"),ImageFormat.Png);
            }
        } finally {foreach(var field in fields)if(field!=null)field.Dispose();}
    }
}
'@
[RoadBlendPreparation]::Run($folder)
Write-Output 'Prepared 15 exterior-only 16px blend fields; matching ports verified.'
