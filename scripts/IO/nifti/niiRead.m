function nii = niiRead(filename)

if(nargin<1)
    error('Usage: nii = niiRead(filename)');
end

%  Check if the file is gzipped
gzipfile = false;
tailing  = 0;
exttype  = true;
if( length(filename) > 2 && strcmp(filename(end-2:end), '.gz') )
    gzipfile = true;
    tailing  = 3;
end
% Check if the file has a proper extension:
if( length(filename) < 4+tailing )
    error('Please check filename.');
end
switch( filename(end-tailing-3:end-tailing) )
    case '.nii'
    case {'.hdr','.img'}
        exttype = false;
    otherwise
        error('Please check filename.');
end

%  Read the dataset header
%
[nii.hdr,nii.filetype,nii.fileprefix,nii.machine] = readNiiHdr(filename,exttype,gzipfile);

if nii.filetype == 0
    nii.hdr = processNiiHdrAnalyze(nii.fileprefix,nii.machine,gzipfile);
    nii.ext = [];
else
    nii.hdr = processNiiHdr(nii.fileprefix,nii.machine,nii.filetype,gzipfile);
    %  Read the header extension
    nii.ext = niiReadExt(filename,exttype,nii.machine,gzipfile);
end

%  Read the dataset body
[nii.img,nii.hdr] = readNiiImg(nii.hdr,nii.filetype,nii.fileprefix,nii.machine,gzipfile);

nii.untouch = 1;

end

