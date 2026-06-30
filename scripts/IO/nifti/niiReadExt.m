function ext = niiReadExt( filename, exttype, machine, gzipfile )

if(gzipfile)
    mode     = 'rbz';
else
    mode     = 'rb';
end

vox_offset = 0;

fid = fopen( filename, mode, machine );
assert( fid>=0, sprintf('Cannot open file %s for reading',filename) );

if(exttype)
    fread( fid, 108, 'uint8=>uint8' );
    vox_offset = fread(fid,1,'float32');
end

ext = read_extension(fid, vox_offset, gzipfile );

fclose(fid);

end


%---------------------------------------------------------------------
function ext = read_extension(fid, vox_offset, is_gzip)

ext = [];

if ~is_gzip
    if(vox_offset > 0)
        end_of_ext = vox_offset;
    else
        fseek(fid, 0, 'eof');
        end_of_ext = ftell(fid);
    end

    if end_of_ext > 352
        fseek(fid, 348, 'bof');
        ext.extension = fread(fid, 4, 'uint8')';
    end
else
    fread(fid, 348, 'uint8=>uint8');
    ext.extension = fread(fid, 4, 'uint8')';

    if vox_offset > 0
        end_of_ext = vox_offset;
    else
        end_of_ext = Inf; % Read until feof(fid) is true
    end
end

if isempty(ext) || ext.extension(1) == 0
    ext = [];
    return;
end

i = 1;
read_bytes = 352;

while true
    if ~is_gzip
        if ftell(fid) >= end_of_ext, break; end
    else
        if feof(fid) || read_bytes >= end_of_ext, break; end
    end

    esize_raw = fread(fid, 1, 'int32');
    if isempty(esize_raw)
        break;
    end

    ext.section(i).esize = esize_raw;
    ext.section(i).ecode = fread(fid, 1, 'int32');

    bytes_to_read = ext.section(i).esize - 8;
    ext.section(i).edata = char(fread(fid, bytes_to_read, 'uint8')');

    read_bytes = read_bytes + ext.section(i).esize;

    i = i + 1;
end

if isfield(ext, 'section')
    ext.num_ext = length(ext.section);
else
    ext = [];
end
end

