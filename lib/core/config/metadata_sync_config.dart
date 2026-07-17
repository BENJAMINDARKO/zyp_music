// lib/core/config/metadata_sync_config.dart

class MetadataSyncConfig {
  // 1. GitHub Configurations (Mapped directly to your repository!)
  static const String githubUsername = "BENJAMINDARKO";
  static const String repoName = "zyp_music";
  static const String branch = "main";

  // 2. Real, Fully-Formulated jsDelivr CDN URLs
  static const String proximityMatrixCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/genre_proximity_matrix.json";
      
  static const String normalizationCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/genre_normalization.json";
      
  static const String countryRegionCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/country_to_region.json";

  // 3. Supabase Credentials
  static const String supabaseUrl = "https://wltbtvzmljsdoqvlthyw.supabase.co";
  static const String supabaseAnonKey = "sb_publishable_VeUpNYJHUsSwVxmJfCx4AQ_bpQ9r_B_";
  
  // Local document storage keys
  static const String proximityFilename = "dynamic_genre_proximity_matrix.json";
  static const String normalizationFilename = "dynamic_genre_normalization.json";
  static const String countryRegionFilename = "dynamic_country_to_region.json";
}
