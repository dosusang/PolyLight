#ifndef TEST_AREA_LIGHTING_INCLUDED
#define TEST_AREA_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

real3 ComputeEdgeFactor(real3 V1, real3 V2)
{
    float subtendedAngle;

    float  V1oV2  = dot(V1, V2);
    real3 V1xV2  = cross(V1, V2);               // Plane normal (tangent to the unit sphere)
    float  sqLen  = saturate(1 - V1oV2 * V1oV2); // length(V1xV2) = abs(sin(angle))
    float  rcpLen = rsqrt(max(FLT_EPS, sqLen));  // Make sure it is finite
#if 0
    float y = rcpLen * acos(V1oV2);
#else
    // Let y[x_] = ArcCos[x] / Sqrt[1 - x^2].
    // Range reduction: since ArcCos[-x] == Pi - ArcCos[x], we only need to consider x on [0, 1].
    float x = abs(V1oV2);
    // Limit[y[x], x -> 1] == 1,
    // Limit[y[x], x -> 0] == Pi/2.
    // The approximation is exact at the endpoints of [0, 1].
    // Max. abs. error on [0, 1] is 1.33e-6 at x = 0.0036.
    // Max. rel. error on [0, 1] is 8.66e-7 at x = 0.0037.
    float y = HALF_PI + x * (-0.99991 + x * (0.783393 + x * (-0.649178 + x * (0.510589 + x * (-0.326137 + x * (0.137528 + x * -0.0270813))))));

    if (V1oV2 < 0)
    {
        y = rcpLen * PI - y;
    }

#endif

    return V1xV2 * y;
}

real3 PolygonFormFactor(real4x3 L, real3 L4, uint n)
{
    // The length cannot be zero since we have already checked
    // that the light has a non-zero effective area,
    // and thus its plane cannot pass through the origin.
    L[0] = normalize(L[0]);
    L[1] = normalize(L[1]);
    L[2] = normalize(L[2]);

    switch (n)
    {
        case 3:
            L[3] = L[0];
            break;
        case 4:
            L[3] = normalize(L[3]);
            L4   = L[0];
            break;
        case 5:
            L[3] = normalize(L[3]);
            L4   = normalize(L4);
            break;
    }

    // If the magnitudes of a pair of edge factors are
    // nearly the same, catastrophic cancellation may occur:
    // https://en.wikipedia.org/wiki/Catastrophic_cancellation
    // For the same reason, the value of the cross product of two
    // nearly collinear vectors is prone to large errors.
    // Therefore, the algorithm is inherently numerically unstable
    // for area lights that shrink to a line (or a point) after
    // projection onto the unit sphere.
    real3 F  = ComputeEdgeFactor(L[0], L[1]);
          F += ComputeEdgeFactor(L[1], L[2]);
          F += ComputeEdgeFactor(L[2], L[3]);
    if (n >= 4)
          F += ComputeEdgeFactor(L[3], L4);
    if (n == 5)
          F += ComputeEdgeFactor(L4, L[0]);

    return INV_TWO_PI * F; // The output may be projected onto the tangent plane (F.z) to yield signed irradiance.
}

float PolygonIrradiance(real4x3 L, out real3 F)
{
    // 1. ClipQuadToHorizon

    // detect clipping config
    uint config = 0;
    if (L[0].z > 0) config += 1;
    if (L[1].z > 0) config += 2;
    if (L[2].z > 0) config += 4;
    if (L[3].z > 0) config += 8;

    // The fifth vertex for cases when clipping cuts off one corner.
    // Due to a compiler bug, copying L into a vector array with 5 rows
    // messes something up, so we need to stick with the matrix + the L4 vertex.
    real3 L4 = L[3];

    // This switch is surprisingly fast. Tried replacing it with a lookup array of vertices.
    // Even though that replaced the switch with just some indexing and no branches, it became
    // way, way slower - mem fetch stalls?

    // clip
    uint n = 0;
    switch (config)
    {
    case 0: // clip all
        break;

    case 1: // V1 clip V2 V3 V4
        n = 3;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[3].z * L[0] + L[0].z * L[3];
        break;

    case 2: // V2 clip V1 V3 V4
        n = 3;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
        break;

    case 3: // V1 V2 clip V3 V4
        n = 4;
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
        L[3] = -L[3].z * L[0] + L[0].z * L[3];
        break;

    case 4: // V3 clip V1 V2 V4
        n = 3;
        L[0] = -L[3].z * L[2] + L[2].z * L[3];
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
        break;

    case 5: // V1 V3 clip V2 V4: impossible
        break;

    case 6: // V2 V3 clip V1 V4
        n = 4;
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
        break;

    case 7: // V1 V2 V3 clip V4
        n = 5;
        L4 = -L[3].z * L[0] + L[0].z * L[3];
        L[3] = -L[3].z * L[2] + L[2].z * L[3];
        break;

    case 8: // V4 clip V1 V2 V3
        n = 3;
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
        L[1] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] = L[3];
        break;

    case 9: // V1 V4 clip V2 V3
        n = 4;
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        L[2] = -L[2].z * L[3] + L[3].z * L[2];
        break;

    case 10: // V2 V4 clip V1 V3: impossible
        break;

    case 11: // V1 V2 V4 clip V3
        n = 5;
        L[3] = -L[2].z * L[3] + L[3].z * L[2];
        L[2] = -L[2].z * L[1] + L[1].z * L[2];
        break;

    case 12: // V3 V4 clip V1 V2
        n = 4;
        L[1] = -L[1].z * L[2] + L[2].z * L[1];
        L[0] = -L[0].z * L[3] + L[3].z * L[0];
        break;

    case 13: // V1 V3 V4 clip V2
        n = 5;
        L[3] = L[2];
        L[2] = -L[1].z * L[2] + L[2].z * L[1];
        L[1] = -L[1].z * L[0] + L[0].z * L[1];
        break;

    case 14: // V2 V3 V4 clip V1
        n = 5;
        L4 = -L[0].z * L[3] + L[3].z * L[0];
        L[0] = -L[0].z * L[1] + L[1].z * L[0];
        break;

    case 15: // V1 V2 V3 V4
        n = 4;
        break;
    }
    if (n == 0) return 0;
    // 2. Integrate
    F = PolygonFormFactor(L, L4, n); // After the horizon clipping.
    // 3. Compute irradiance
    return max(0, F.z);
}

real3x3 GetOrthoBasisViewNormal(real3 V, real3 N, float unclampedNdotV)
{
    real3x3 orthoBasisViewNormal;
    orthoBasisViewNormal[0] = normalize(V - N * unclampedNdotV);
    orthoBasisViewNormal[2] = N;
    orthoBasisViewNormal[1] = cross(orthoBasisViewNormal[2], orthoBasisViewNormal[0]);
    return orthoBasisViewNormal;
}

#endif