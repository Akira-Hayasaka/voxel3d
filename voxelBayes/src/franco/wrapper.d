// dmd -I~/Documents/scid/generated/headers -m32 -c franco/wrapper.d

module franco.wrapper;

import std.stdio;

import scid.matrix;
import franco.matrix;
import franco.types;

extern (C) francoVoxel!float francoReconstructCovfub(francoPhoto!(float, ubyte) *fp, int numPhoto, francoParam!float fparam) {
	return francoReconstruct!(float, ubyte, BgModel.Cov)(fp, numPhoto, fparam);
}
extern (C) francoVoxel!float francoReconstructCovfui(francoPhoto!(float, uint) *fp, int numPhoto, francoParam!float fparam) {
	return francoReconstruct!(float, uint, BgModel.Cov)(fp, numPhoto, fparam);
}

extern (C) francoVoxel!float francoReconstructParzenfub(francoPhoto!(float, ubyte) *fp, int numPhoto, francoParam!float fparam) {
	return francoReconstruct!(float, ubyte, BgModel.Parzen)(fp, numPhoto, fparam);
}
extern (C) francoVoxel!float francoReconstructParzenfui(francoPhoto!(float, uint) *fp, int numPhoto, francoParam!float fparam) {
	return francoReconstruct!(float, uint, BgModel.Parzen)(fp, numPhoto, fparam);
}

francoVoxel!Tmat francoReconstruct(Tmat, Timg, BgModel M)(francoPhoto!(Tmat, Timg) *fp, int numPhoto, francoParam!Tmat fparam) {
	francoVoxel!Tmat fVoxel;
	
	photoModel!(Tmat, Timg)[] models;
	models.length = numPhoto;
	foreach(i; 0..numPhoto) {
		auto model = new photoModel!(Tmat, Timg)(fp[i]);
		model.intrinsics.writeln;
		model.extrinsics.writeln;
		model.projection.writeln;
		models[i] = model;
	}
	
	auto voxel = new voxelLike!(Tmat, Timg, M);
	voxel.models = models;
	voxel.parameters = fparam;
	voxel.reconstruct;
	fVoxel = voxel.fVoxel;
	
	return fVoxel;
}

//extern (C) alias francoReconstructfub = francoReconstruct!(float, ubyte);

extern(C) int ofmain();
void main() {
	ofmain();
}
