{#
  UDF BigQuery — conversion Lambert-93 (EPSG:2154) → WGS84 (EPSG:4326).
  Ellipsoïde GRS80. Précision < 1 mm sur la France métropolitaine.
  Retourne STRUCT<lat FLOAT64, lon FLOAT64>, NULL hors des bornes métropolitaines.

  Invocation :
    {{ lambert93_to_latlon('coordonneeLambertAbscisseEtablissement', 'coordonneeLambertOrdonneeEtablissement') }}.lat

  Création UDF :
    • Automatique via on-run-start (lambert93_udf_ddl())
    • Manuelle : dbt run-operation create_lambert93_udf
#}

{% macro lambert93_to_latlon(x, y) %}
    `{{ target.project }}.{{ target.dataset }}.lambert93_to_latlon`(
        SAFE_CAST({{ x }} AS FLOAT64),
        SAFE_CAST({{ y }} AS FLOAT64)
    )
{% endmacro %}


{% macro lambert93_udf_ddl() %}
    CREATE OR REPLACE FUNCTION
        `{{ target.project }}.{{ target.dataset }}.lambert93_to_latlon`(x FLOAT64, y FLOAT64)
    RETURNS STRUCT<lat FLOAT64, lon FLOAT64>
    LANGUAGE js AS r"""
      // Projection : Lambert-93 (EPSG:2154) -> WGS84 (EPSG:4326)
      // Ellipsoïde : GRS80 — RGF93 ≈ WGS84 à < 1 cm, aucune transformation de datums
      var a  = 6378137.0;
      var e  = 0.0818191908426215;
      var e2 = e * e;

      var phi1    = 44.0 * Math.PI / 180;
      var phi2    = 49.0 * Math.PI / 180;
      var phi0    = 46.5 * Math.PI / 180;
      var lambda0 =  3.0 * Math.PI / 180;
      var X0      = 700000;
      var Y0      = 6600000;

      function m_func(phi) {
        return Math.cos(phi) / Math.sqrt(1 - e2 * Math.sin(phi) * Math.sin(phi));
      }
      function t_func(phi) {
        var sinPhi = Math.sin(phi);
        return Math.tan(Math.PI / 4 - phi / 2) /
               Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2);
      }

      var m1 = m_func(phi1), m2 = m_func(phi2);
      var t0 = t_func(phi0), t1 = t_func(phi1), t2 = t_func(phi2);
      var n  = (Math.log(m1) - Math.log(m2)) / (Math.log(t1) - Math.log(t2));
      var F  = m1 / (n * Math.pow(t1, n));
      var r0 = a * F * Math.pow(t0, n);

      // Validation bornes France métropolitaine
      if (x === null || y === null) return null;
      if (x < 100000 || x > 1300000 || y < 6000000 || y > 7300000) return null;

      var xi      = x - X0;
      var eta     = r0 - (y - Y0);
      var r_prime = Math.sqrt(xi * xi + eta * eta);
      var theta   = Math.atan2(xi, eta);
      var t_prime = Math.pow(r_prime / (a * F), 1.0 / n);

      var phi = Math.PI / 2 - 2 * Math.atan(t_prime);
      for (var i = 0; i < 10; i++) {
        var sinPhi = Math.sin(phi);
        phi = Math.PI / 2 - 2 * Math.atan(
          t_prime * Math.pow((1 - e * sinPhi) / (1 + e * sinPhi), e / 2)
        );
      }

      var lambda = theta / n + lambda0;
      return { lat: phi * 180 / Math.PI, lon: lambda * 180 / Math.PI };
    """
{% endmacro %}


{% macro create_lambert93_udf() %}
    {% do run_query(lambert93_udf_ddl()) %}
    {% do log("UDF lambert93_to_latlon créée dans " ~ target.project ~ "." ~ target.dataset, info=true) %}
{% endmacro %}
