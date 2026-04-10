{% macro lambert93_to_latlon(x, y) %}
  `{{ target.project }}.{{ target.dataset }}.lambert93_to_latlon`(
    SAFE_CAST({{ x }} AS FLOAT64),
    SAFE_CAST({{ y }} AS FLOAT64)
  )
{% endmacro %}

{% macro create_lambert93_udf() %}
  {% set sql %}
    CREATE OR REPLACE FUNCTION
      `{{ target.project }}.{{ target.dataset }}.lambert93_to_latlon`(x FLOAT64, y FLOAT64)
    RETURNS STRUCT<lat FLOAT64, lon FLOAT64>
    LANGUAGE js AS r"""

      /*
        Projection : Lambert-93 (EPSG:2154) -> WGS84 (EPSG:4326)
        Ellipsoïde : GRS80
        Méthode    : Projection conique conforme de Lambert (inverse exacte)
        Précision  : < 1 mm sur la France métropolitaine
        Note       : RGF93 ≈ WGS84 à < 1 cm — aucune transformation de datums nécessaire
      */

      // --- Paramètres GRS80 ---
      var a  = 6378137.0;           // demi-grand axe (m)
      var e  = 0.0818191908426215;  // première excentricité
      var e2 = e * e;

      // --- Paramètres Lambert-93 ---
      var phi1    = 44.0 * Math.PI / 180;  // parallèle standard 1
      var phi2    = 49.0 * Math.PI / 180;  // parallèle standard 2
      var phi0    = 46.5 * Math.PI / 180;  // latitude d'origine
      var lambda0 =  3.0 * Math.PI / 180;  // longitude d'origine (méridien de Greenwich)
      var X0      = 700000;                 // fausse abscisse (m)
      var Y0      = 6600000;                // fausse ordonnée (m)

      // --- Fonctions auxiliaires ---
      function m_func(phi) {
        return Math.cos(phi) / Math.sqrt(1 - e2 * Math.sin(phi) * Math.sin(phi));
      }

      function t_func(phi) {
        var sinPhi = Math.sin(phi);
        return Math.tan(Math.PI / 4 - phi / 2) /
               Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2);
      }

      // --- Constantes de la projection ---
      var m1 = m_func(phi1);
      var m2 = m_func(phi2);
      var t0 = t_func(phi0);
      var t1 = t_func(phi1);
      var t2 = t_func(phi2);

      var n  = (Math.log(m1) - Math.log(m2)) / (Math.log(t1) - Math.log(t2));
      var F  = m1 / (n * Math.pow(t1, n));
      var r0 = a * F * Math.pow(t0, n);

      // --- Conversion inverse Lambert -> géographique ---
      var xi      = x - X0;
      var eta     = r0 - (y - Y0);
      var r_prime = Math.sqrt(xi * xi + eta * eta);  // rayon polaire
      var theta   = Math.atan2(xi, eta);              // angle polaire

      var t_prime = Math.pow(r_prime / (a * F), 1.0 / n);

      // Latitude : solution itérative (converge en ~5 itérations, 10 par sécurité)
      var phi = Math.PI / 2 - 2 * Math.atan(t_prime);
      for (var i = 0; i < 10; i++) {
        var sinPhi = Math.sin(phi);
        phi = Math.PI / 2 - 2 * Math.atan(
          t_prime * Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2)
        );
      }

      // Longitude
      var lambda = theta / n + lambda0;

      return {
        lat: phi    * 180 / Math.PI,
        lon: lambda * 180 / Math.PI
      };
    """;
  {% endset %}

  {% do run_query(sql) %}
  {% do log("UDF lambert93_to_latlon créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}

-- dbt run-operation create_lambert93_udf
