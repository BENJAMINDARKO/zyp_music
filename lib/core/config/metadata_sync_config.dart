class MetadataSyncConfig {
  // 1. GitHub Configuration
  static const String githubUsername = "BENJAMINDARKO";
  static const String repoName = "zyp_music";
  static const String branch = "main";

  // 2. jsDelivr CDN URLs (Linked directly to your main branch files)
  static const String proximityMatrixCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/genre_proximity_matrix.json";
      
  static const String normalizationCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/genre_normalization.json";
      
  static const String countryRegionCdnUrl = 
      "https://cdn.jsdelivr.net/gh/$githubUsername/$repoName@$branch/assets/data/country_to_region.json";

  // 3. Supabase Credentials (FILL THESE IN from Supabase settings)
  static const String supabaseUrl = "https://YOUR_PROJECT_ID.supabase.co"; 
  static const String supabaseAnonKey = "YOUR_PUBLISHABLE_PUBLIC_ANON_KEY"; 
  
  // Local document storage keys
  static const String proximityFilename = "dynamic_genre_proximity_matrix.json";
  static const String normalizationFilename = "dynamic_genre_normalization.json";
  static const String countryRegionFilename = "dynamic_country_to_region.json";
}
