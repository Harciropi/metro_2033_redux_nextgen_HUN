// Resource index reader/writer for the Steam next-gen Metro Redux layout.
// Does not locate games or install files. Callers control all output paths.
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

namespace Metro2033Hu {
    public sealed class ResourceEntry {
        public int Record; public ushort Archive; public uint Offset, Packed, Unpacked;
        internal string Name; internal int First, Count; internal bool Directory;
    }
    public sealed class ResourceIndex {
        public static void AtomicWrite(string path,byte[] bytes) {
            string temporary=path+".new-"+Guid.NewGuid().ToString("N");
            try {File.WriteAllBytes(temporary,bytes);if(File.Exists(path))File.Replace(temporary,path,null);else File.Move(temporary,path);}
            finally {if(File.Exists(temporary))File.Delete(temporary);}
        }
        public readonly byte[] Data;
        public readonly List<string> Archives = new List<string>();
        public readonly Dictionary<string,ResourceEntry> Files = new Dictionary<string,ResourceEntry>(StringComparer.OrdinalIgnoreCase);
        readonly List<ResourceEntry> entries = new List<ResourceEntry>();
        readonly uint fileCount, directoryCount;
        readonly int archiveEnd, entriesEnd;
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false,true);
        public ResourceIndex(byte[] data) {
            Data=data;
            using(var stream=new MemoryStream(data,false)) using(var r=new BinaryReader(stream)) {
                if(data.Length<44) throw new InvalidDataException("INDEX_TRUNCATED");
                stream.Position=24;
                uint archives=r.ReadUInt32(); fileCount=r.ReadUInt32(); directoryCount=r.ReadUInt32();
                if(archives==0 || archives>=65535 || fileCount>1000000 || directoryCount>1000000) throw new InvalidDataException("INDEX_LAYOUT");
                for(int a=0;a<archives;a++) {
                    string name=ReadString(r);
                    if(Path.GetFileName(name)!=name || name.Contains("/") || name.Contains("\\") || !name.EndsWith(".vfs"+name[name.Length-1],StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("ARCHIVE_NAME");
                    Archives.Add(name);uint count=r.ReadUInt32();
                    if(count>10000)throw new InvalidDataException("ARCHIVE_LAYOUT");
                    for(uint i=0;i<count;i++)ReadString(r);
                    r.ReadUInt32();
                }
                archiveEnd=checked((int)stream.Position);
                for(uint i=0;i<fileCount;i++) {
                    var e=new ResourceEntry(); e.Record=checked((int)stream.Position);
                    ushort type=r.ReadUInt16();
                    if(type==0) {e.Archive=r.ReadUInt16();e.Offset=r.ReadUInt32();e.Unpacked=r.ReadUInt32();e.Packed=r.ReadUInt32();if(e.Archive>=archives)throw new InvalidDataException("ARCHIVE_ID");}
                    else if(type==8){e.Directory=true;e.Count=r.ReadUInt16();e.First=checked((int)r.ReadUInt32());}
                    else throw new InvalidDataException("ENTRY_TYPE");
                    int length=r.ReadByte();byte xor=r.ReadByte();
                    if(length<1)throw new InvalidDataException("ENTRY_NAME");
                    byte[] name=r.ReadBytes(length);if(name.Length!=length)throw new EndOfStreamException();
                    for(int n=0;n<length-1;n++)name[n]^=xor;
                    e.Name=Utf8.GetString(name,0,length-1);entries.Add(e);
                }
                entriesEnd=checked((int)stream.Position);
                if((long)entriesEnd+directoryCount*20L+8!=data.Length)throw new InvalidDataException("INDEX_TRAILER");
            }
            if(entries.Count==0 || !entries[0].Directory)throw new InvalidDataException("INDEX_ROOT");
            Walk(0,"",new HashSet<int>());
        }
        static string ReadString(BinaryReader r) {
            var bytes=new List<byte>();
            for(int n=0;n<32768;n++){byte b=r.ReadByte();if(b==0)return Utf8.GetString(bytes.ToArray());bytes.Add(b);}
            throw new InvalidDataException("STRING_LENGTH");
        }
        void Walk(int i,string prefix,HashSet<int> ancestors) {
            if(i<0 || i>=entries.Count || !ancestors.Add(i))throw new InvalidDataException("INDEX_TREE");
            ResourceEntry e=entries[i];string p=(prefix+"/"+e.Name).TrimStart('/').Replace('\\','/');
            if(p.Contains("../") || p.StartsWith("/"))throw new InvalidDataException("RESOURCE_PATH");
            if(e.Directory) {
                if(e.First<0 || (long)e.First+e.Count>entries.Count)throw new InvalidDataException("INDEX_TREE");
                for(int child=e.First;child<e.First+e.Count;child++)Walk(child,p,ancestors);
            } else {
                if(Files.ContainsKey(p))throw new InvalidDataException("DUPLICATE_RESOURCE");Files.Add(p,e);
            }
            ancestors.Remove(i);
        }
        public byte[] Extract(string folder,string resource) {
            ResourceEntry e;if(!Files.TryGetValue(resource,out e))throw new InvalidDataException("RESOURCE_MISSING");
            string path=Path.Combine(folder,Archives[e.Archive]);
            using(var s=File.OpenRead(path)) {
                if((long)e.Offset+e.Packed>s.Length || e.Unpacked>134217728 || e.Packed>150994944)throw new InvalidDataException("RESOURCE_RANGE");
                s.Position=e.Offset;byte[] raw=new byte[e.Packed];int read=0;
                while(read<raw.Length){int n=s.Read(raw,read,raw.Length-read);if(n==0)throw new EndOfStreamException();read+=n;}
                if(e.Packed==e.Unpacked)return raw;
                return DecodeBlocks(raw,checked((int)e.Unpacked));
            }
        }
        static uint U32(byte[] b,int p){if(p<0 || p+4>b.Length)throw new InvalidDataException("LZ4_HEADER");return BitConverter.ToUInt32(b,p);}
        static byte[] DecodeBlocks(byte[] raw,int expected) {
            byte[] output=new byte[expected];int input=0,write=0;
            while(input<raw.Length) {
                uint packed=U32(raw,input),unpacked=U32(raw,input+4);
                if(packed<8 || packed>raw.Length-input)throw new InvalidDataException("LZ4_BLOCK");
                int end=checked(input+(int)packed);input+=8;
                if(packed==unpacked) {
                    int n=end-input;if(n>output.Length-write)throw new InvalidDataException("LZ4_RANGE");Buffer.BlockCopy(raw,input,output,write,n);write+=n;input=end;continue;
                }
                int start=write;
                while(input<end) {
                    int token=raw[input++],literal=token>>4,match=token&15;
                    if(literal==15){int n;do{if(input>=end)throw new InvalidDataException("LZ4_LITERAL");n=raw[input++];literal=checked(literal+n);}while(n==255);}
                    if(literal>end-input || literal>output.Length-write)throw new InvalidDataException("LZ4_RANGE");
                    Buffer.BlockCopy(raw,input,output,write,literal);input+=literal;write+=literal;
                    if(input==end)break;
                    if(input+2>end)throw new InvalidDataException("LZ4_OFFSET");int distance=raw[input]|raw[input+1]<<8;input+=2;
                    if(distance==0 || distance>write || distance>65535)throw new InvalidDataException("LZ4_DISTANCE");
                    if(match==15){int n;do{if(input>=end)throw new InvalidDataException("LZ4_MATCH");n=raw[input++];match=checked(match+n);}while(n==255);}
                    match+=4;if(match>output.Length-write)throw new InvalidDataException("LZ4_RANGE");
                    for(int n=0;n<match;n++){output[write]=output[write-distance];write++;}
                }
                if(write-start!=unpacked)throw new InvalidDataException("LZ4_BLOCK_SIZE");
            }
            if(write!=expected)throw new InvalidDataException("LZ4_FINAL_SIZE");return output;
        }
        public byte[][] Overlay(string archiveName,string[] paths,byte[][] contents) {
            bool exists=Archives.Exists(delegate(string a){return String.Equals(a,archiveName,StringComparison.OrdinalIgnoreCase);});
            if(paths.Length!=contents.Length || paths.Length==0 || exists || Path.GetFileName(archiveName)!=archiveName || archiveName.Contains("\\") || archiveName.Contains("/") || !archiveName.EndsWith(".vfs0",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("OVERLAY_LAYOUT");
            byte[] modified=(byte[])Data.Clone();var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            byte[] archive;
            using(var ms=new MemoryStream()) using(var w=new BinaryWriter(ms)) {
                w.Write(0u);w.Write(0u);
                for(int i=0;i<paths.Length;i++) {
                    ResourceEntry e;
                    if(!seen.Add(paths[i]) || !Files.TryGetValue(paths[i],out e))throw new InvalidDataException("OVERLAY_RESOURCE");
                    uint offset=checked((uint)ms.Position),size=checked((uint)contents[i].Length);
                    using(var es=new MemoryStream(modified,true))using(var ew=new BinaryWriter(es)) {
                        es.Position=e.Record+2;ew.Write(checked((ushort)Archives.Count));ew.Write(offset);ew.Write(size);ew.Write(size);
                    }
                    w.Write(contents[i]);
                }
                uint payload=checked((uint)ms.Length-8);w.Write(3u);w.Write(16u);w.Write(Data,8,16);
                ms.Position=4;w.Write(payload);archive=ms.ToArray();
            }
            byte[] index;
            using(var ms=new MemoryStream())using(var w=new BinaryWriter(ms)) {
                w.Write(Data,0,24);w.Write(checked((uint)Archives.Count+1));w.Write(fileCount);w.Write(directoryCount);
                w.Write(Data,36,archiveEnd-36);w.Write(Utf8.GetBytes(archiveName));w.Write((byte)0);w.Write(0u);w.Write(checked((uint)archive.Length));
                w.Write(modified,archiveEnd,entriesEnd-archiveEnd);w.Write(Data,entriesEnd,Data.Length-entriesEnd);index=ms.ToArray();
            }
            var check=new ResourceIndex(index);if(check.Files.Count!=Files.Count || check.Archives.Count!=Archives.Count+1)throw new InvalidDataException("OVERLAY_VERIFY");
            return new byte[][]{index,archive};
        }
    }
}

namespace Metro2033Hu {
 public static class BannerFilter {
  sealed class Pe {
   internal byte[] B;int sections,sectionCount,dirs;
   internal Pe(byte[] b){B=b;Require(b.Length>=256 && U16(0)==0x5a4d);int pe=I32(0x3c);Require(U32(pe)==0x4550 && U16(pe+4)==0x8664);sectionCount=U16(pe+6);int optional=pe+24;Require(U16(optional)==0x20b);dirs=optional+112;sections=optional+U16(pe+20);Require(sectionCount>0 && sectionCount<100);At(sections,sectionCount*40);}
   internal int At(int off,int count){Require(off>=0 && count>=0 && off<=B.Length-count);return off;}
   internal ushort U16(int p){return BitConverter.ToUInt16(B,At(p,2));}
   internal uint U32(int p){return BitConverter.ToUInt32(B,At(p,4));}
   internal int I32(int p){return BitConverter.ToInt32(B,At(p,4));}
   internal int Rva(uint rva,int bytes){for(int n=0;n<sectionCount;n++){int s=sections+n*40;uint va=U32(s+12),size=U32(s+16),raw=U32(s+20);if(rva>=va && (ulong)(rva-va)+(uint)bytes<=size)return At(checked((int)(raw+rva-va)),bytes);}throw new InvalidDataException("BANNER_LAYOUT");}
   string Str(uint rva){int p=Rva(rva,1),end=p;while(end<B.Length && B[end]!=0 && end-p<512)end++;Require(end<B.Length && end-p<512);return Encoding.ASCII.GetString(B,p,end-p);}
   internal uint Export(string name){uint er=U32(dirs),sz=U32(dirs+4);int e=Rva(er,40);uint count=U32(e+24),functions=U32(e+28),names=U32(e+32),ordinals=U32(e+36);Require(count<100000);for(uint n=0;n<count;n++){uint nr=U32(Rva(names+n*4,4));if(Str(nr)!=name)continue;ushort ordinal=U16(Rva(ordinals+n*2,2));uint fn=U32(Rva(functions+(uint)ordinal*4,4));Require(fn<er || fn>=er+sz);return fn;}throw new InvalidDataException("BANNER_LAYOUT");}
   internal int[] Function(uint rva){uint dir=U32(dirs+3*8),size=U32(dirs+3*8+4);Require(size>0 && size%12==0);int p=Rva(dir,checked((int)size));for(int i=0;i<size;i+=12){uint begin=U32(p+i),end=U32(p+i+4);if(begin==rva){Require(end>begin && end-begin<=8192);return new[]{Rva(begin,checked((int)(end-begin))),checked((int)(end-begin))};}}throw new InvalidDataException("BANNER_LAYOUT");}
  }
  static void Require(bool ok){if(!ok)throw new InvalidDataException("BANNER_LAYOUT");}
  static int Find(byte[] b,int start,int length,byte[] pattern){int found=-1;for(int p=start;p<=start+length-pattern.Length;p++){int i=0;while(i<pattern.Length && (pattern[i]==0xff || b[p+i]==pattern[i]))i++;if(i!=pattern.Length)continue;Require(found<0);found=p;}Require(found>=0);return found;}
  public static int[] Offsets(byte[] data){
   var pe=new Pe(data);uint cached=pe.Export("prosdk_banner_get_banner_spaces_from_cache");pe.Export("prosdk_banner_get_banner_spaces");pe.Export("prosdk_banner_get_banner_spaces_result_release");
   int[] f=pe.Function(cached);
   // Locate the native result converter through the cache export's call.
   byte[] call={0x48,0x8d,0x54,0x24,0x20,0x48,0x8b,0xcb,0xe8,0xff,0xff,0xff,0xff};int c=Find(data,f[0],f[1],call);int disp=pe.I32(c+9);uint convert=checked((uint)((long)cached+c-f[0]+13+disp));int[] cv=pe.Function(convert);
   // Both branches already have native empty-array paths. Suppress only
   // their non-empty alternatives; metadata and native callback flow stay.
   byte[] first={0x48,0x8b,0x4a,0x10,0x48,0x8b,0x42,0x18,0x48,0x3b,0xc8,0xff,0xff,0x33,0xf6,0x49,0x89,0x75,0x18,0x49,0x89,0x75,0x10,0xe9};
   byte[] second={0x49,0x8b,0x4c,0x24,0x28,0x49,0x8b,0x44,0x24,0x30,0x48,0x3b,0xc8,0xff,0xff,0x49,0x89,0x75,0x28,0x49,0x89,0x75,0x20,0xe9};
   int a=Find(data,cv[0],cv[1],first)+11,b=Find(data,cv[0],cv[1],second)+13;
   bool original=data[a]==0x75 && data[a+1]==0x0f && data[b]==0x75 && data[b+1]==0x0d;
   bool filtered=data[a]==0x90 && data[a+1]==0x90 && data[b]==0x90 && data[b+1]==0x90;
   Require(original || filtered);return new[]{a,a+1,b,b+1};
  }
  static int InitializationGate(byte[] data) {
   var pe=new Pe(data);int[] f=pe.Function(pe.Export("prosdk_init"));
   // Keep the SDK's existing prologue, native early-error return (108), and
   // epilogue. Suppress only the version-success branch into initialization.
   byte[] pattern={0x41,0x81,0xf8,0xff,0xff,0xff,0xff,0xff,0xff,0xb8,0x6c,0,0,0,0x48,0x81,0xc4,0xff,0xff,0xff,0xff,0x5e,0x5b,0x5d,0xc3};
   int p=Find(data,f[0],Math.Min(f[1],128),pattern)+7;
   Require((data[p]==0x74 && data[p+1]==0x10)||(data[p]==0x90 && data[p+1]==0x90));
   return p;
  }
  public static string Inspect(byte[] data){
   int[] offsets=Offsets(data);int gate=InitializationGate(data);
   bool legacy=data[offsets[0]]==0x90,disabled=data[gate]==0x90;
   // The 2033 installer never owned converter/vector patches. Reject them.
   Require(!legacy);
   return disabled?"FILTERED":"ORIGINAL";
  }
  public static byte[] Apply(byte[] data){
   Inspect(data);int gate=InitializationGate(data);
   byte[] result=(byte[])data.Clone();
   // Retain every other SDK byte, including native banner conversion.
   result[gate]=0x90;result[gate+1]=0x90;return result;
  }
 }
}
