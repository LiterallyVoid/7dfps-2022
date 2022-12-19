pub usingnamespace @cImport({
    @cInclude("glad/gl.h");

    @cDefine("GLFW_DLL", {});
    @cInclude("GLFW/glfw3.h");

    @cInclude("stb_image.h");
    @cInclude("stb_truetype.h");
    @cInclude("unistd.h");

    @cInclude("vorbis/codec.h");
    @cInclude("vorbis/vorbisfile.h");

    @cInclude("AL/al.h");
    @cInclude("AL/alc.h");
});
