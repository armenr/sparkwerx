/* Private EGL pbuffer rendering: no compositor, DRM master, window, or input. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <stdio.h>
#include <string.h>

static int probe(EGLDeviceEXT device) {
    EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_DEVICE_EXT, device, NULL);
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLint count = 0;
    EGLConfig config;
    int result = 1;
    const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE
    };
    const EGLint surface_attributes[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, NULL, NULL))
        return 1;
    if (!eglBindAPI(EGL_OPENGL_API) ||
        !eglChooseConfig(display, config_attributes, &config, 1, &count) || count != 1)
        goto done;
    surface = eglCreatePbufferSurface(display, config, surface_attributes);
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, NULL);
    if (surface == EGL_NO_SURFACE || context == EGL_NO_CONTEXT ||
        !eglMakeCurrent(display, surface, surface, context))
        goto done;
    const char *vendor = (const char *)glGetString(GL_VENDOR);
    if (vendor == NULL || strstr(vendor, "NVIDIA") == NULL) {
        fprintf(stderr, "FAIL|egl|renderer is not NVIDIA hardware\n");
        goto done;
    }
    for (int frame = 0; frame < 2; ++frame) {
        unsigned char pixel[4] = {0};
        glClearColor(frame == 0 ? 1.0f : 0.0f, frame == 1 ? 1.0f : 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glFinish();
        glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        if (glGetError() != GL_NO_ERROR || pixel[frame] != 255 ||
            pixel[1 - frame] != 0 || pixel[2] != 0) {
            fprintf(stderr, "FAIL|egl|GPU framebuffer readback did not match\n");
            goto done;
        }
    }
    puts("PASS|egl|Nix GLVND with factory NVIDIA driver; two pbuffer colors verified");
    result = 0;
done:
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (context != EGL_NO_CONTEXT)
        eglDestroyContext(display, context);
    if (surface != EGL_NO_SURFACE)
        eglDestroySurface(display, surface);
    eglTerminate(display);
    return result;
}

int main(void) {
    PFNEGLQUERYDEVICESEXTPROC query_devices =
        (PFNEGLQUERYDEVICESEXTPROC)eglGetProcAddress("eglQueryDevicesEXT");
    EGLDeviceEXT devices[8];
    EGLint count = 0;
    if (query_devices == NULL || !query_devices(8, devices, &count) || count < 1) {
        fprintf(stderr, "FAIL|egl|no EGL device available (0x%x)\n", eglGetError());
        return 1;
    }
    for (int i = 0; i < count; ++i) {
        if (probe(devices[i]) == 0)
            return 0;
    }
    fprintf(stderr, "FAIL|egl|no NVIDIA device completed private pbuffer rendering (0x%x)\n", eglGetError());
    return 1;
}
